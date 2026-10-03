# frozen_string_literal: true

# One photograph of a physical build, with the line that says what it is showing.
class BuildPhoto < ApplicationRecord
  include CountedTowardStorage
  MAX_BYTES = 8.megabytes
  MAX_CAPTION_LENGTH = 140

  belongs_to :build, inverse_of: :photos

  # A posted thing: it can be reacted to, and written on.
  include Reactable

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 480, 300 ]
    attachable.variant :display, resize_to_limit: [ 1600, 1600 ]
  end

  normalizes :caption, with: ->(value) { value.to_s.strip }

  validates :caption, length: { maximum: MAX_CAPTION_LENGTH }, allow_blank: true
  validate :image_is_an_image

  before_create :append_to_end

  private
    def storage_owner
      build&.user
    end

    def image_is_an_image
      return unless image.attached?

      if image.blob.byte_size > MAX_BYTES
        errors.add(:image, "must be smaller than #{MAX_BYTES / 1.megabyte} MB")
      end

      return if image.blob.content_type.to_s.start_with?("image/")

      errors.add(:image, "must be an image")
    end

    def append_to_end
      self.position = (build&.photos&.maximum(:position) || -1) + 1
    end
end
