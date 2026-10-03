# frozen_string_literal: true

# A titled block of text on a profile: what the era called Interests, Music,
# Heroes, or whatever the owner wanted. Ordered, because the order is the layout.
class Blurb < ApplicationRecord
  # Generous for a paragraph, bounded so a page cannot be built out of unbounded
  # blocks.
  MAX_BODY_LENGTH = 20_000
  MAX_TITLE_LENGTH = 60

  belongs_to :user

  normalizes :title, with: ->(value) { value.to_s.strip }

  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  validates :body, length: { maximum: MAX_BODY_LENGTH }

  scope :in_order, -> { order(:position, :id) }

  before_create :append_to_end

  # The body as it may be rendered: the same allowlist as a profile page's markup,
  # because a blurb is markup an author wrote and it reaches the same page.
  def rendered_body
    ProfileMarkup.render(body).html
  end

  # Move this blurb one place earlier or later. Positions are rewritten as a dense
  # sequence so the order on the page is the layout's order, not the order things
  # happened to be created in.
  def move!(direction)
    siblings = user.blurbs.in_order.to_a
    index = siblings.index(self)
    return if index.nil?

    target = direction.to_s == "up" ? index - 1 : index + 1
    return if target.negative? || target >= siblings.size

    siblings[index], siblings[target] = siblings[target], siblings[index]
    siblings.each_with_index { |blurb, position| blurb.update_column(:position, position) }
  end

  private
    def append_to_end
      self.position = (user&.blurbs&.maximum(:position) || -1) + 1 if position.to_i.zero?
    end
end
