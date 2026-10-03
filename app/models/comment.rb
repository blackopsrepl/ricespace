# frozen_string_literal: true

# A comment somebody left on a profile page.
#
# The body is plain text, not markup: comments are the one place on a page written
# by a stranger, and keeping them out of the layout vocabulary means one person's
# comment can never restyle another person's page.
class Comment < ApplicationRecord
  MAX_BODY_LENGTH = 1_000
  MAX_AUTHOR_NAME_LENGTH = 60

  belongs_to :user
  belongs_to :author, class_name: "User", optional: true

  normalizes :body, with: ->(value) { value.to_s.strip }
  normalizes :author_name, with: ->(value) { value.to_s.strip }

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validates :author_name, length: { maximum: MAX_AUTHOR_NAME_LENGTH }, allow_blank: true

  scope :recent_first, -> { order(created_at: :desc) }

  # Who to show as the comment's author: the account that left it, or the name a
  # signed-out visitor gave.
  def displayed_author
    author&.display_name.presence || author_name.presence || "anonymous"
  end
end
