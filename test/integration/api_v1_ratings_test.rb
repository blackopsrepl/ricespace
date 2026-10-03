# frozen_string_literal: true

require "test_helper"

# Reactions over the API.
#
# The browser has its own tests; these cover the two things an agent needs and the browser
# cannot give it: reading the reaction of the page its token speaks for, and expressing an
# opinion about somebody else's. The second is the only action on this site that is
# available to an agent and is about *another* account's page.
class ApiV1RatingsTest < ActionDispatch::IntegrationTest
  setup do
    @page = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @agent = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @token = AgentToken.issue(user: @agent, name: "the CLI")
    @headers = { "Authorization" => "Bearer #{@token.plaintext}" }
  end

  test "the read is the reaction on the page the token speaks for" do
    # The token is cordelia's, so this is cordelia's page — the number her own dashboard
    # shows. Reading *somebody else's* score is not what this endpoint is for; the answer
    # to "what do people think of @vittorio" is on @vittorio's page.
    @agent.reactions.create!(author: @page, score: Rating::LIKE)
    ron = User.create!(username: "ronald", email_address: "r@example.com", password: "correct horse battery")
    @agent.reactions.create!(author: ron, score: Rating::DISLIKE)

    get api_v1_ratings_url, headers: @headers

    assert_response :success
    rating = response.parsed_body["rating"]

    assert_equal "cordelia", rating["username"]
    assert_equal 0, rating["score"]
    assert_equal 1, rating["likes"]
    assert_equal 1, rating["dislikes"]
    assert_equal 2, rating["raters"]
  end

  test "the read counts what was posted on the page, not only the page" do
    rice = @agent.create_showcase!(title: "my desk")
    rice.reactions.create!(author: @page, score: Rating::LIKE)

    get api_v1_ratings_url, headers: @headers

    assert_response :success
    rating = response.parsed_body["rating"]

    assert_equal 1, rating["score"], "a like on the rice lifts the page"
    assert_equal 0, @agent.reactions.count, "the page's own reactions are still the page's own"
  end

  test "the read carries no opinion of your own page, because there cannot be one" do
    @page.reactions.create!(author: @agent, score: Rating::LIKE)

    get api_v1_ratings_url, headers: @headers

    assert_response :success
    # `yours` is an opinion *about* the page. On your own page there is none to have — you
    # cannot react to yourself — so it is nothing here, and it is the write response that
    # carries what you said about somebody else.
    assert_nil response.parsed_body["rating"]["yours"]
  end

  test "the write response carries what you said, separately from the score" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "dislike" }

    assert_response :success
    body = response.parsed_body

    # The page's score is other people's; `yours` is this account's, and they are two
    # different facts that happen to arrive together.
    assert_equal(-1, body["rating"]["score"])
    assert_equal "dislike", body["yours"]
  end

  test "an agent likes somebody's page" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "like" }

    assert_response :success
    assert_equal "like", response.parsed_body["yours"]
    assert_equal true, response.parsed_body["changed"]
    assert_equal 1, @page.reload.score
  end

  test "saying the same thing twice changes nothing, and says so" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "like" }
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "like" }

    assert_response :success
    # Not a toggle: this is a `PUT`, and a retried request must not flip an opinion.
    assert_equal false, response.parsed_body["changed"]
    assert_equal 1, @page.reload.score
    assert_equal 1, @page.reactions.count
  end

  test "none takes the reaction back, and saying none twice is not a change" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "like" }
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "none" }

    assert_equal true, response.parsed_body["changed"]
    assert_equal 0, @page.reload.score

    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "none" }

    assert_equal false, response.parsed_body["changed"]
    assert_equal 0, @page.reload.score
  end

  test "changing your mind moves the one reaction rather than adding another" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "like" }
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "dislike" }

    assert_equal(-1, @page.reload.score)
    assert_equal 1, @page.reactions.count
  end

  # ── reacting to a post, over the API ─────────────────────────────────────────────────────

  test "an agent reacts to somebody's rice, not only to their page" do
    rice = @page.create_showcase!(title: "my desk")

    put api_v1_rate_post_url("vittorio", "showcase", rice.id), headers: @headers, params: { rating: "like" }

    assert_response :success
    assert_equal "like", response.parsed_body["yours"]
    assert_equal true, response.parsed_body["changed"]
    assert_equal 1, rice.reload.score
  end

  test "a post that is not on this page is a 404" do
    elsewhere = User.create!(username: "somebody", email_address: "s@example.com",
      password: "correct horse battery")
    other_rice = elsewhere.create_showcase!(title: "not this page")

    put api_v1_rate_post_url("vittorio", "showcase", other_rice.id), headers: @headers, params: { rating: "like" }

    assert_response :not_found
    assert_equal "unknown_post", response.parsed_body["error"]["code"]
  end

  test "a kind that does not exist is refused" do
    put api_v1_rate_post_url("vittorio", "spaceship", 1), headers: @headers, params: { rating: "like" }

    assert_response :unprocessable_content
    assert_equal "unknown_kind", response.parsed_body["error"]["code"]
  end

  # ── what cannot be done ──────────────────────────────────────────────────────────────────

  test "a page cannot react to itself" do
    own = AgentToken.issue(user: @page, name: "vittorio's own")
    headers = { "Authorization" => "Bearer #{own.plaintext}" }

    put api_v1_rate_page_url("vittorio"), headers: headers, params: { rating: "like" }

    assert_response :unprocessable_content
    assert_equal "own_post", response.parsed_body["error"]["code"]
    assert_equal 0, @page.reload.score
  end

  test "a page cannot react to its own rice" do
    rice = @page.create_showcase!(title: "my desk")
    own = AgentToken.issue(user: @page, name: "vittorio's own")
    headers = { "Authorization" => "Bearer #{own.plaintext}" }

    put api_v1_rate_post_url("vittorio", "showcase", rice.id), headers: headers, params: { rating: "like" }

    assert_response :unprocessable_content
    assert_equal "own_post", response.parsed_body["error"]["code"]
    assert_equal 0, rice.reload.score
  end

  test "a page that does not exist is a 404 rather than a new page" do
    put api_v1_rate_page_url("nobody"), headers: @headers, params: { rating: "like" }

    assert_response :not_found
    assert_equal "unknown_page", response.parsed_body["error"]["code"]
  end

  test "an opinion that is not one is refused" do
    put api_v1_rate_page_url("vittorio"), headers: @headers, params: { rating: "banana" }

    assert_response :unprocessable_content
    assert_equal "unknown_rating", response.parsed_body["error"]["code"]
    assert_equal 0, @page.reload.score
  end

  test "the ratings endpoint needs a token" do
    get api_v1_ratings_url
    assert_response :unauthorized

    put api_v1_rate_page_url("vittorio"), params: { rating: "like" }
    assert_response :unauthorized
  end
end
