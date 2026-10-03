# frozen_string_literal: true

require "test_helper"

# The showcase from the browser: an owner builds the main event on their page, and a
# visitor sees it.
class ShowcaseFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "an owner describes their rice and it appears on their page" do
    patch showcase_url, params: { showcase: {
      title: "Catppuccin on the Framework", summary: "a quiet setup",
      details: "<p>ghostty and waybar</p>",
      hardware: "Framework 13", window_manager: "Hyprland", bar: "waybar",
      terminal: "ghostty", font: "JetBrains Mono", theme: "catppuccin"
    } }

    assert_redirected_to studio_url

    get profile_url(@user)

    assert_response :success
    assert_match "Catppuccin on the Framework", response.body
    assert_match "ghostty and waybar", response.body
    assert_match "Framework 13", response.body
    assert_match "Hyprland", response.body
    assert_match 'id="showcase"', response.body
  end

  test "a shot is added, becomes the cover, and can be moved or removed" do
    patch showcase_url, params: { showcase: { title: "a rice" } }
    post showcase_shots_url, params: { showcase_shot: { image: upload } }

    assert_redirected_to edit_showcase_url
    shot = @user.showcase.reload.shots.sole
    assert_predicate shot.image, :attached?

    get profile_url(@user)

    assert_match(/<img[^>]+representations[^>]+rice\.png/, response.body)

    delete showcase_shot_url(shot)

    assert_redirected_to edit_showcase_url
    assert_empty @user.showcase.reload.shots
  end

  test "the studio and the showcase editor both point at the rice" do
    get studio_url

    assert_response :success
    assert_match "the rice", response.body
    assert_match "Build your showcase", response.body

    get edit_showcase_url

    assert_response :success
    assert_match "Your showcase", response.body
    assert_match "the six things people ask about a rice", response.body
  end

  test "the front page leads with the rices" do
    showcase = @user.create_showcase(title: "Catppuccin on the Framework", summary: "a quiet setup")
    shot = showcase.shots.create!
    shot.image.attach(io: Rails.root.join("test", "fixtures", "files", "rice.png").open,
      filename: "rice.png", content_type: "image/png")

    get root_url

    assert_response :success
    assert_match "Catppuccin on the Framework", response.body
    assert_match(/<img[^>]+representations[^>]+rice\.png/, response.body)
  end

  test "a visitor cannot edit somebody else's showcase" do
    other = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")

    get edit_showcase_url
    assert_response :success

    delete session_url
    post session_url, params: { email_address: other.email_address, password: "correct horse battery" }

    patch showcase_url, params: { showcase: { title: "not mine" } }

    assert_redirected_to studio_url
    assert_nil @user.reload.showcase
  end

  private
    def upload(filename = "rice.png", content_type = "image/png")
      Rack::Test::UploadedFile.new(Rails.root.join("test", "fixtures", "files", "rice.png"), content_type,
        original_filename: filename)
    end
end
