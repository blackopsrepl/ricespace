# frozen_string_literal: true

require "test_helper"

# The rest of a page over the API: the lists a client manages as lists.
class ApiV1PageTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @friend = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @token = AgentToken.issue(user: @user, name: "the CLI")
    @headers = { "Authorization" => "Bearer #{@token.plaintext}" }
  end

  test "a page reads with every list on it" do
    @user.stream_links.create!(url: "https://youtu.be/dQw4w9WgXcQ", title: "a video")
    @user.demos.create!(title: "a demo", group_name: "Farbrausch", release_year: 2003, ranking: 1,
      url: "https://youtu.be/dQw4w9WgXcQ")
    @user.builds.create!(title: "a rack", kind: "rack", specs: "4 nodes")
    @user.friendships.create!(friend: @friend)
    @user.blurbs.create!(title: "Interests", body: "<p>modems</p>")

    get api_v1_page_url, headers: @headers

    assert_response :success
    page = response.parsed_body["page"]

    assert_equal "vittorio", page["username"]
    assert_equal [ { "platform" => "youtube", "url" => "https://youtu.be/dQw4w9WgXcQ",
      "title" => "a video" } ], page["links"]
    assert_equal "a demo", page["demos"].first["title"]
    assert_equal 1, page["demos"].first["placing"]
    # The demo's link is a video, so it embeds rather than standing as a link.
    assert_equal true, page["demos"].first["embeds"]
    assert_equal "rack", page["builds"].first["kind"]
    assert_equal [ "cordelia" ], page["friends"]
    assert_equal "Interests", page["blurbs"].first["title"]
  end

  test "an empty page reads as empty lists rather than nothing" do
    get api_v1_page_url, headers: @headers

    assert_response :success
    page = response.parsed_body["page"]

    assert_empty page["links"]
    assert_empty page["demos"]
    assert_empty page["builds"]
    assert_empty page["friends"]
    assert_empty page["blurbs"]
  end

  test "a list is replaced whole, and only the lists that were sent" do
    @user.blurbs.create!(title: "Interests", body: "<p>modems</p>")

    put api_v1_page_url, headers: @headers, params: {
      page: { friends: [ { username: "cordelia" } ] }
    }

    assert_response :success
    page = response.parsed_body["page"]

    assert_equal [ "cordelia" ], page["friends"]
    # Not in the request, so untouched.
    assert_equal "Interests", page["blurbs"].first["title"]
  end

  test "sending an empty list clears it" do
    @user.stream_links.create!(url: "https://youtu.be/dQw4w9WgXcQ")

    put api_v1_page_url, headers: @headers, params: { page: { links: [] } }

    assert_response :success
    assert_empty response.parsed_body["page"]["links"]
    assert_empty @user.stream_links.reload
  end

  test "a link that is not a video on a known service is refused, and nothing is written" do
    @user.stream_links.create!(url: "https://youtu.be/dQw4w9WgXcQ")

    put api_v1_page_url, headers: @headers, params: {
      page: { links: [ { url: "https://evil.example/watch?v=x" } ] }
    }

    assert_response :unprocessable_content
    error = response.parsed_body["error"]

    assert_equal "invalid_page", error["code"]
    assert_match "YouTube", error["details"].to_s
    # The list that was already there is intact — a refused write changes nothing.
    assert_equal 1, @user.stream_links.reload.count
  end

  test "a friend who does not exist is refused, and nothing is written" do
    @user.friendships.create!(friend: @friend)

    put api_v1_page_url, headers: @headers, params: {
      page: { friends: [ { username: "nobody" } ] }
    }

    assert_response :unprocessable_content
    assert_match "nobody", response.parsed_body["error"]["details"].to_s
    assert_equal [ @friend ], @user.friendships.reload.map(&:friend)
  end

  test "demos and hardware are written with their facts" do
    put api_v1_page_url, headers: @headers, params: {
      page: {
        demos: [ { title: "fr-025", group: "Farbrausch", party: "Breakpoint", year: 2003,
                   platform: "Windows", category: "64k intro", placing: 1 } ],
        builds: [ { title: "the rack", kind: "rack", specs: "4 nodes", cooling: "one big fan",
                    details: "<p>loud</p>" } ]
      }
    }

    assert_response :success
    demo = @user.demos.sole

    assert_equal 2003, demo.release_year
    assert_equal 1, demo.ranking
    assert_equal "1st place", demo.placing_note
    assert_equal "rack", @user.builds.sole.kind
  end

  test "blurb bodies are markup, stored verbatim and cleaned when rendered" do
    put api_v1_page_url, headers: @headers, params: {
      page: { blurbs: [ { title: "Interests", body: "<p>modems</p><script>alert(1)</script>" } ] }
    }

    assert_response :success
    blurbs = @user.blurbs.reload.sole

    assert_includes blurbs.body, "<script"
    refute_includes blurbs.rendered_body, "<script"
  end

  test "the page endpoint needs a token" do
    get api_v1_page_url

    assert_response :unauthorized
  end
end
