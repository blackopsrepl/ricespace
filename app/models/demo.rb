# frozen_string_literal: true

# A demoscene demo: the category a page gets when it is about the scene rather than about a
# desktop.
#
# A demo is not a video. A video is a video; a demo has a group, a party, a year, a
# platform, a category and often a ranking, and those are the things somebody lists it for
# — "second place at Revision 2019, 64k intro, Windows" is the whole content of the entry.
# So this is its own model with those fields rather than a title and a URL, and the fields
# are what a demo list can be read for.
#
# The url is optional and read exactly like every other video on a page (VideoSource): it
# may be a YouTube upload of a demo, or a catalogue page on a site like pouet, which is not
# a video at all and is therefore a link rather than an embed.
class Demo < ApplicationRecord
  MAX_TITLE_LENGTH = 120
  MAX_LINE_LENGTH = 80

  # What a demo ran on. A short vocabulary rather than free text, because the value is
  # meant to be readable as a column and comparable across entries.
  PLATFORMS = [
    "Amiga", "Atari ST", "Atari VCS", "C64", "MS-DOS", "Windows", "Linux", "macOS",
    "Dreamcast", "PlayStation", "Nintendo 64", "Game Boy", "ZX Spectrum", "BBC Micro",
    "Acorn Archimedes", "Browser", "Android", "iOS", "Other"
  ].freeze

  # The categories a demo is entered in, in the rough order a party awards them.
  CATEGORIES = [
    "demo", "64k intro", "32k intro", "16k intro", "4k intro", "1k intro", "256b intro",
    "intro", "wild", "wild demo", "animation", "music", "graphics", "game"
  ].freeze

  belongs_to :user

  # A posted thing: it can be reacted to, and written on.
  include Reactable

  normalizes :title, with: ->(value) { value.to_s.strip }
  normalizes :group_name, with: ->(value) { value.to_s.strip }
  normalizes :party, with: ->(value) { value.to_s.strip }
  normalizes :platform, with: ->(value) { value.to_s.strip }
  normalizes :category, with: ->(value) { value.to_s.strip }
  normalizes :url, with: ->(value) { value.to_s.strip }
  normalizes :watch_note, with: ->(value) { value.to_s.strip }

  validates :title, presence: true, length: { maximum: MAX_TITLE_LENGTH }
  validates :group_name, :party, length: { maximum: MAX_LINE_LENGTH }, allow_blank: true
  validates :category, length: { maximum: MAX_LINE_LENGTH }, allow_blank: true
  validates :platform, inclusion: { in: PLATFORMS }, allow_blank: true
  validates :release_year,
    numericality: { only_integer: true, greater_than_or_equal_to: 1980, less_than_or_equal_to: 2100 },
    allow_nil: true
  # A ranking is a placing at a party competition: 1 is first place.
  validates :ranking,
    numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 999 },
    allow_nil: true

  validate :url_is_usable

  scope :in_order, -> { order(:release_year, :title) }

  # The embed for this demo's url, when the url is a video on a service this site knows.
  # nil for a catalogue link, which is the common case and not an error.
  def embed
    permalink = url.presence
    return if permalink.nil?

    StreamEmbed.for_url(permalink, title: title)
  end

  # "Revision 2019", or just the year, or just the party — whenever any of it is known.
  def release_note
    [ party.presence, release_year ].compact.reject(&:blank?).join(" ").presence
  end

  # "2nd at Revision 2019" — the placing as it would be said.
  def placing_note
    return if ranking.nil?

    suffix = { 1 => "st", 2 => "nd", 3 => "rd" }[ranking] || "th"
    "#{ranking}#{suffix} place"
  end

  private
    # The url may be any catalogued page — pouet, a scene party's site, a personal page —
    # so this does not insist on a known service. It insists only on what it must: an
    # http(s) address with no credentials, so that the value written into an href cannot
    # be a `javascript:` URL or carry a password.
    def url_is_usable
      return if url.blank?
      return if VideoSource.parse(url)

      # Not a video, so it is only ever a link. It still has to be a link.
      uri = begin
        URI.parse(url)
      rescue URI::InvalidURIError
        nil
      end

      if uri.nil? || !%w[ http https ].include?(uri.scheme) || uri.host.blank? || uri.userinfo.present?
        errors.add(:url, "must be an http(s) address")
      end
    end
end
