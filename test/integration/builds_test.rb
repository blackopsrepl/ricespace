# frozen_string_literal: true

require "test_helper"

# The hardware category from the browser: a build, a photo of it, and what is in it.
class BuildsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "an owner lists a build with a photo and it appears on their page" do
    post builds_url, params: { build: {
      title: "The rack in the spare room", kind: "rack",
      summary: "four nodes and a lot of noise",
      specs: "4× mini-ITX, 64 GB each", cooling: "one very large fan",
      details: "<p>built over a weekend</p>",
      photo: upload, photo_caption: "from the front"
    } }

    assert_redirected_to studio_url

    get profile_url(@user)

    assert_response :success
    assert_match 'id="hardware"', response.body
    assert_match "The rack in the spare room", response.body
    assert_match "four nodes and a lot of noise", response.body
    assert_match "4× mini-ITX, 64 GB each", response.body
    assert_match "one very large fan", response.body
    assert_match "built over a weekend", response.body
    assert_match(/<img[^>]+representations[^>]+photo\.png/, response.body)
    assert_match "from the front", response.body
  end

  test "a second photo is added to a build on its own" do
    post builds_url, params: { build: { title: "a closet", kind: "homelab" } }
    build = @user.builds.sole

    post add_photo_build_url(build), params: { photo: upload, caption: "the back" }

    assert_redirected_to studio_url
    assert_equal 1, build.reload.photos.size
    assert_equal "the back", build.photos.sole.caption
  end

  test "a photo is removed without removing the build" do
    post builds_url, params: { build: { title: "a closet" } }
    build = @user.builds.sole
    post add_photo_build_url(build), params: { photo: upload, caption: "the back" }

    delete remove_photo_build_url(build, photo_id: build.photos.sole.id)

    assert_redirected_to studio_url
    assert_empty build.reload.photos
    assert_predicate build, :persisted?
  end

  test "several builds live on one page" do
    post builds_url, params: { build: { title: "a rack", kind: "rack" } }
    post builds_url, params: { build: { title: "a cooling loop", kind: "cooling" } }

    get profile_url(@user)

    assert_match "a rack", response.body
    assert_match "a cooling loop", response.body
    assert_match "2 builds", response.body
  end

  test "a build is edited and removed" do
    post builds_url, params: { build: { title: "a rack" } }
    build = @user.builds.sole

    patch build_url(build), params: { build: { cooling: "six fans" } }

    assert_redirected_to studio_url
    assert_equal "six fans", build.reload.cooling

    delete build_url(build)

    assert_redirected_to studio_url
    assert_empty @user.builds
  end

  test "a build with no title is refused, and says so" do
    post builds_url, params: { build: { title: "" } }

    assert_redirected_to studio_url
    assert_match "Title can't be blank", flash[:alert]
    assert_empty @user.builds
  end

  test "the studio offers the hardware category" do
    get studio_url

    assert_response :success
    assert_match "Hardware", response.body
    assert_match "Add build", response.body
    assert_match "rack", response.body
  end

  private
    def upload
      Rack::Test::UploadedFile.new(Rails.root.join("test", "fixtures", "files", "rice.png"), "image/png",
        original_filename: "photo.png")
    end
end
