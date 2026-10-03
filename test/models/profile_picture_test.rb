# frozen_string_literal: true

require "test_helper"

class ProfilePictureTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @picture = @user.create_profile_picture
  end

  test "an attached image is kept, and its sizes are generated" do
    attach(@picture, "rice.png", "image/png")

    assert_predicate @picture.reload.image, :attached?
    # The variants are the two the page uses; a variant that cannot be built is a broken
    # page, so this exercises one rather than trusting the declaration.
    assert_predicate @picture.image.variant(:thumb).processed, :present?
  end

  test "a file that is not an image is refused" do
    attach(@picture, "payload.txt", "text/plain", body: "not an image at all")

    refute_predicate @picture, :valid?
    assert @picture.errors[:image].any?
  end

  test "an image is judged by its bytes, not by the name it was sent under" do
    # Active Storage identifies the real content type, so a PNG called .txt is kept:
    # the check is what the file is, not what the upload claimed.
    attach(@picture, "actually-a-png.txt", "text/plain")

    assert_predicate @picture, :valid?
  end

  test "an image over the size limit is refused" do
    attach(@picture, "big.png", "image/png", bytes: ProfilePicture::MAX_BYTES + 1)

    refute_predicate @picture, :valid?
    assert_match "smaller than", @picture.errors[:image].to_s
  end

  test "a picture belongs to one account" do
    assert_not ProfilePicture.new.valid?
  end

  test "deleting an account takes its picture" do
    attach(@picture, "rice.png", "image/png")

    assert_difference -> { ProfilePicture.count } => -1 do
      @user.destroy
    end
  end

  private
    def attach(picture, filename, content_type, bytes: nil, body: nil)
      body ||= bytes ? ("0" * bytes) : Rails.root.join("test", "fixtures", "files", "rice.png").binread
      picture.image.attach(io: StringIO.new(body), filename: filename, content_type: content_type)
    end
end
