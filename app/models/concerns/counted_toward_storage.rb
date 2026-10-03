# frozen_string_literal: true

# A picture that counts against its account's storage.
#
# The per-file ceilings live on the models (`ProfilePicture::MAX_BYTES` and so on) and bound
# one upload. That is a different question from how much one account may keep, and the answer
# has to be the same whichever door the upload came through — the studio's three forms today,
# the API's `POST /api/v1/images` alongside them, and whatever is added next. So the check is
# written once, here, and included by everything that stores a picture; the number itself is
# `User::STORAGE_LIMIT`.
#
# A record being replaced does not count against itself: uploading a new profile picture is not
# an account growing by two pictures.
module CountedTowardStorage
  extend ActiveSupport::Concern

  included do
    validate :account_has_room_for_the_picture, if: -> { image.attached? }
  end

  private
    # Each model says what it hangs off: a profile picture belongs to the account, a rice shot
    # to the rice, a hardware photo to the build.
    def storage_owner
      raise NotImplementedError, "#{self.class} must define #storage_owner"
    end

    def account_has_room_for_the_picture
      owner = storage_owner
      return if owner.nil?

      adding = image.blob.byte_size.to_i
      return unless owner.over_storage_limit?(adding, excluding: self)

      errors.add(:image, "would take this account past its #{owner.class::STORAGE_LIMIT / 1.megabyte} MB of pictures")
    end
end
