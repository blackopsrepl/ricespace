# frozen_string_literal: true

require "test_helper"

# The picture path from the browser: the upload that had no test, and no tables.
class PictureUploadTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "an owner uploads a picture and their page shows it" do
    patch profile_picture_url, params: { profile_picture: { image: upload } }

    assert_redirected_to studio_url
    assert_predicate @user.reload.profile_picture.image, :attached?

    get profile_url(@user)

    assert_response :success
    # The rendered image is a variant URL under the representations endpoint, so the
    # assertion is on the element and the blob rather than on one form of the URL.
    assert_match "profile-pic", response.body
    assert_match(/<img[^>]+src="[^"]*representations[^"]*rice\.png"/, response.body)
  end

  test "a refused upload says why rather than raising" do
    patch profile_picture_url, params: { profile_picture: { image: upload_text } }

    assert_redirected_to studio_url
    assert_match "must be an image", flash[:alert]
    # No picture record was created, so there is nothing on the page to show.
    assert_nil @user.reload.profile_picture
  end

  test "an upload with no file attached says so" do
    patch profile_picture_url, params: { profile_picture: {} }

    assert_redirected_to studio_url
    assert_predicate flash[:alert], :present?
  end

  test "an owner removes their picture" do
    patch profile_picture_url, params: { profile_picture: { image: upload } }

    delete profile_picture_url

    assert_redirected_to studio_url
    assert_nil @user.reload.profile_picture
  end

  test "uploading a new picture replaces the old one" do
    patch profile_picture_url, params: { profile_picture: { image: upload } }
    first = @user.reload.profile_picture.image.blob.id

    patch profile_picture_url, params: { profile_picture: { image: upload("again.png", "image/png") } }

    assert_not_equal first, @user.reload.profile_picture.image.blob.id
    assert_equal 1, @user.profile_picture.image.blob.attachments.count
  end

  private
    def upload(filename = "rice.png", content_type = "image/png")
      Rack::Test::UploadedFile.new(Rails.root.join("test", "fixtures", "files", "rice.png"), content_type,
        original_filename: filename)
    end

    # A real text file: Active Storage identifies content, so the fixture has to be
    # something that is not an image rather than an image with a misleading name.
    def upload_text
      path = Rails.root.join("tmp", "not-an-image.txt")
      path.write("this is not an image")
      Rack::Test::UploadedFile.new(path, "text/plain", original_filename: "payload.txt")
    end
end
