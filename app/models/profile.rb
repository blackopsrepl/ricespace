# frozen_string_literal: true

# A profile page: the markup its owner wrote, and the revision it is at.
#
# The document column is deliberately untrusted text. It is cleaned on the way
# out (see ProfileMarkup), never on the way in, so the stored page is always what
# its author wrote and every tightened rule applies to every existing page at
# once.
class Profile < ApplicationRecord
  # The largest stored page accepted. Generous for a profile, bounded so a
  # single write cannot store an unbounded document.
  MAX_DOCUMENT_LENGTH = 200_000

  belongs_to :user

  # The page as stored, uninterpreted.
  normalizes :document, with: ->(value) { value.to_s }

  validates :document, length: { maximum: MAX_DOCUMENT_LENGTH }

  # One revision per change of content. Nothing here refuses a write: the studio
  # and the agent API each compare the version their caller edited against this
  # one, because each owes its caller a different answer for a lost write (a form
  # the owner can resubmit, a 409 the agent must handle).
  before_save :bump_version, if: :document_changed?

  # The markup as it may be rendered, sanitized for the current rule set.
  def markup
    ProfileMarkup.render(document)
  end

  private
    def bump_version
      self.version = version.to_i + 1
    end
end
