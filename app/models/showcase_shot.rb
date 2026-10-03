# frozen_string_literal: true

# One picture of a rice, with the line that says what it is showing.
class ShowcaseShot < ApplicationRecord
  MAX_BYTES = 8.megabytes
  MAX_CAPTION_LENGTH = 140

  belongs_to :showcase, inverse_of: :shots

  has_one_attached :image do |attachable|
    attachable.variant :thumb, resize_to_fill: [ 480, 300 ]
    attachable.variant :display, resize_to_limit: [ 1600, 1600 ]
  end

  normalizes :caption, with: ->(value) { value.to_s.strip }

  validates :caption, length: { maximum: MAX_CAPTION_LENGTH }, allow_blank: true
  validate :image_is_an_image

  before_create :append_to_end

  # Move this shot one place earlier or later, so the one the page leads with is the
  # owner's choice rather than the order the files were uploaded in.
  def move!(direction)
    siblings = showcase.shots.to_a
    index = siblings.index(self)
    return if index.nil?

    target = direction.to_s == "up" ? index - 1 : index + 1
    return if target.negative? || target >= siblings.size

    siblings[index], siblings[target] = siblings[target], siblings[index]
    siblings.each_with_index { |shot, position| shot.update_column(:position, position) }
  end

  private
    def image_is_an_image
      return unless image.attached?

      if image.blob.byte_size > MAX_BYTES
        errors.add(:image, "must be smaller than #{MAX_BYTES / 1.megabyte} MB")
      end

      return if image.blob.content_type.to_s.start_with?("image/")

      errors.add(:image, "must be an image")
    end

    def append_to_end
      self.position = (showcase&.shots&.maximum(:position) || -1) + 1
    end
end
