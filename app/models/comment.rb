# frozen_string_literal: true

# A comment somebody left on a profile page.
#
# The body is plain text, not markup: comments are the one place on a page written
# by another person, and keeping them out of the layout vocabulary means one person's
# comment can never restyle another person's page.
#
# An author is always an account — comments are signed in, so there is no name to type
# and nothing anonymous on a page.
class Comment < ApplicationRecord
  MAX_BODY_LENGTH = 1_000

  belongs_to :user
  belongs_to :author, class_name: "User"

  normalizes :body, with: ->(value) { value.to_s.strip }

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  scope :recent_first, -> { order(created_at: :desc) }

  # The account that left the comment. Its name comes from the account, so changing
  # your display name changes what your old comments say — there is no stale copy.
  def displayed_author
    author&.display_name.presence || "somebody"
  end
end
