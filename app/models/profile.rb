# frozen_string_literal: true

# A profile page: the markup its owner wrote, the one song that plays when somebody
# opens it, and the revision it is at.
#
# The document column is deliberately untrusted text. It is cleaned on the way out
# (see ProfileMarkup), never on the way in, so the stored page is always what its
# author wrote and every tightened rule applies to every existing page at once.
class Profile < ApplicationRecord
  # The largest stored page accepted. Generous for a profile, bounded so a single
  # write cannot store an unbounded document.
  MAX_DOCUMENT_LENGTH = 200_000

  # Where a song may be fetched from, held to the same policy as every other URL an
  # author supplies: http(s) on the open web, or this site. Anchored with \A and \z
  # so a value cannot satisfy the prefix and continue past it — `https://x` and
  # `https://x\njavascript:` are not the same thing to every consumer of the value.
  SONG_URL = %r{\Ahttps?://[^\s]+\z}i

  belongs_to :user

  # The page as stored, uninterpreted.
  normalizes :document, with: ->(value) { value.to_s }
  normalizes :song_url, with: ->(value) { value.to_s.strip }

  validates :document, length: { maximum: MAX_DOCUMENT_LENGTH }
  validates :interests, length: { maximum: 10_000 }
  validates :song_url,
    format: { with: SONG_URL, message: "must be an http(s) address" },
    allow_blank: true
  validates :song_title, length: { maximum: 120 }, allow_blank: true

  # One revision per change of content. Nothing here refuses a write: the studio
  # and the agent API each compare the version their caller edited against this one,
  # because each owes its caller a different answer for a lost write (a form the
  # owner can resubmit, a 409 the agent must handle).
  before_save :bump_version, if: :document_changed?

  # The page as its author wrote it, cleaned for display: markup and stylesheet
  # together. The stylesheet is not optional — without it a profile is a document
  # with its layout missing.
  def rendered
    ProfileMarkup.render(document)
  end

  # Whether the page is meant to play something.
  def song?
    song_url.present?
  end

  private
    def bump_version
      self.version = version.to_i + 1
    end
end
