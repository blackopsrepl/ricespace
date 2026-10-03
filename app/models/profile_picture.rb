# frozen_string_literal: true

# A profile page's picture.
#
# An upload, not a URL: a page is a photograph, and every alternative social
# product of the era that asked people to host their own image first lost them at
# that step. The variants are the sizes the page's anatomy actually uses — the
# picture beside the name, and the thumbnail on a friends list or a comment.
class ProfilePicture < ApplicationRecord
  # A profile picture is an image, not a payload. This bounds the upload before
  # any processing happens.
  MAX_BYTES = 5.megabytes
  MAX_DIMENSION = 4_000

  belongs_to :user

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 100, 100 ]
    attachable.variant :display, resize_to_limit: [ 320, 320 ]
  end

  validate :image_is_an_image

  private
    def image_is_an_image
      return unless image.attached?

      if image.blob.byte_size > MAX_BYTES
        errors.add(:image, "must be smaller than #{MAX_BYTES / 1.megabyte} MB")
      end

      return if image.blob.content_type.to_s.start_with?("image/")

      errors.add(:image, "must be an image")
    end
end
