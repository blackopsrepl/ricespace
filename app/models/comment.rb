# frozen_string_literal: true

# Something somebody wrote on something somebody posted.
#
# The body is plain text, not markup: a comment is the one part of a page written by another
# person, and keeping it out of the layout vocabulary means one person's comment can never
# restyle another person's page.
#
# What was written on is a pair — a kind and an id — so the same wall works under a page, the
# rice, a shot of that rice, a build, a demo or a link. A wall on a page is for the page; a
# wall under a build is for the build.
#
# The author is always an account. Comments are signed in, so there is no name to type and
# nothing anonymous on a page.
class Comment < ApplicationRecord
  MAX_BODY_LENGTH = 1_000

  belongs_to :commentable, polymorphic: true
  belongs_to :author, class_name: "User"

  normalizes :body, with: ->(value) { value.to_s.strip }

  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  scope :recent_first, -> { order(created_at: :desc) }

  # The account that left the comment. Its name comes from the account, so changing your
  # display name changes what your old comments say — there is no stale copy.
  def displayed_author
    author&.display_name.presence || "somebody"
  end

  # The account whose thing this is. Every commentable belongs to one, and it is what decides
  # who may remove a comment.
  def owner
    commentable.respond_to?(:owner) ? commentable.owner : nil
  end
end
