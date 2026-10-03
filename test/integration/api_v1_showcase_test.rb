# frozen_string_literal: true

require "test_helper"

# The showcase over the API: what a local client (the Rust CLI, or an agent) reads and
# writes. The studio is the same record, so this is a second way into one thing rather
# than a second thing.
class ApiV1ShowcaseTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @token = AgentToken.issue(user: @user, name: "the CLI")
    @headers = { "Authorization" => "Bearer #{@token.plaintext}" }
  end

  test "an account with no showcase gets an empty one rather than a 404" do
    get api_v1_showcase_url, headers: @headers

    assert_response :success
    body = response.parsed_body["showcase"]

    assert_equal "vittorio", body["username"]
    assert_nil body["title"]
    assert_empty body["filled"]
    assert_empty body["shots"]
  end

  test "the rice reads with its facts named and its shots listed" do
    showcase = @user.create_showcase(title: "Purple on a ThinkPad", summary: "a quiet setup",
      hardware: "ThinkPad X1 Carbon", window_manager: "Hyprland", theme: "Catppuccin")
    shot = showcase.shots.create!(caption: "the desktop")
    shot.image.attach(io: Rails.root.join("test", "fixtures", "files", "rice.png").open,
      filename: "rice.png", content_type: "image/png")

    get api_v1_showcase_url, headers: @headers

    assert_response :success
    body = response.parsed_body["showcase"]

    assert_equal "Purple on a ThinkPad", body["title"]
    assert_equal "ThinkPad X1 Carbon", body["facts"]["hardware"]
    assert_equal [ { "label" => "hardware", "value" => "ThinkPad X1 Carbon" },
      { "label" => "window manager", "value" => "Hyprland" },
      { "label" => "theme", "value" => "Catppuccin" } ], body["filled"]
    assert_equal 1, body["shots"].size
    assert_equal "the desktop", body["shots"].first["caption"]
    assert_operator body["shots"].first["bytes"], :>, 0
  end

  test "the facts are written, and only the ones that were sent" do
    @user.create_showcase(title: "before", theme: "Nord")

    patch api_v1_showcase_url, headers: @headers, params: {
      showcase: { title: "after", terminal: "ghostty" }
    }

    assert_response :success
    body = response.parsed_body["showcase"]

    assert_equal "after", body["title"]
    assert_equal "ghostty", body["facts"]["terminal"]
    # Not in the request, so untouched.
    assert_equal "Nord", body["facts"]["theme"]
  end

  test "a showcase is created by the first write if there was none" do
    patch api_v1_showcase_url, headers: @headers, params: { showcase: { title: "first" } }

    assert_response :success
    assert_equal "first", @user.reload.showcase.title
  end

  test "a value over the limit is refused with the reasons, not a raise" do
    patch api_v1_showcase_url, headers: @headers, params: {
      showcase: { title: "x" * (Showcase::MAX_LINE_LENGTH + 1) }
    }

    assert_response :unprocessable_content
    body = response.parsed_body["error"]

    assert_equal "invalid_showcase", body["code"]
    assert_match "Title is too long", body["details"].to_s
  end

  test "the details are cleaned the same way a page's markup is" do
    patch api_v1_showcase_url, headers: @headers, params: {
      showcase: { details: "<p>ghostty</p><script>alert(1)</script>" }
    }

    assert_response :success
    # Stored verbatim, cleaned when rendered — the same rule as the page.
    assert_includes @user.reload.showcase.details, "<script"
    refute_includes @user.reload.showcase.rendered_details, "<script"
  end

  test "an agent cannot reach the rice without a valid token" do
    get api_v1_showcase_url

    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body["error"]["code"]
  end
end
