# frozen_string_literal: true

require "test_helper"

# Whole-list replacement, and what it has to survive.
#
# A folder sends a list and expects it to mean "this is the list". Two things follow that the
# page endpoint did not do: setting the same list twice is not a conflict (the entries being
# replaced are the list, not duplicates of it), and a field the column requires but the folder
# omitted has to be filled rather than reaching SQLite as a constraint violation. Both were
# found by pushing a real folder, and both are the difference between a 422 a person can read
# and a 500 they cannot.
class ApiV1PageListsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @friend = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @token = AgentToken.issue(user: @user, name: "the CLI")
    @headers = { "Authorization" => "Bearer #{@token.plaintext}" }
  end

  test "setting the same friends twice is not a duplicate" do
    put api_v1_page_url, headers: @headers, params: { page: { friends: [ { username: "cordelia" } ] } }
    assert_response :success

    put api_v1_page_url, headers: @headers, params: { page: { friends: [ { username: "cordelia" } ] } }

    assert_response :success
    assert_equal [ "cordelia" ], response.parsed_body["page"]["friends"]
  end

  test "setting the same blurbs twice replaces rather than duplicates them" do
    body = { page: { blurbs: [ { title: "Interests", body: "modems" } ] } }

    put api_v1_page_url, headers: @headers, params: body
    assert_response :success
    put api_v1_page_url, headers: @headers, params: body

    assert_response :success
    assert_equal 1, @user.blurbs.reload.count
  end

  test "a hardware entry with a title and nothing else is written, not crashed on" do
    # `builds.details` is NOT NULL with a default. A folder that sets only a title is not
    # wrong, and the answer must be a page rather than a constraint violation.
    put api_v1_page_url, headers: @headers, params: { page: { builds: [ { title: "the bench" } ] } }

    assert_response :success
    build = @user.builds.sole

    assert_equal "the bench", build.title
    assert_equal "", build.details
  end

  test "a refused entry leaves the list it replaced exactly as it was" do
    @user.blurbs.create!(title: "Interests", body: "modems")

    put api_v1_page_url, headers: @headers, params: { page: { blurbs: [ { title: "x", body: "y" } ] } }
    assert_response :success

    # No title is invalid, so this list is refused — and the one that was there must survive.
    put api_v1_page_url, headers: @headers, params: { page: { blurbs: [ { body: "no title" } ] } }

    assert_response :unprocessable_content
    assert_equal [ "x" ], @user.blurbs.reload.map(&:title)
  end

end
