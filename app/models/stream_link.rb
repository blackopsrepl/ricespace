# frozen_string_literal: true

# A video or stream the owner of a page wants shown on it.
#
# Nothing is stored: the video stays on YouTube, Vimeo, X or Twitch, and all this holds is
# the link plus the little that had to be read out of it to build an embed.
#
# That reading is the point of the model — and it lives in VideoSource, so that the same
# rules cover every URL on a page that becomes a frame. What reaches the page is a host
# this application chose and an id checked against the service's own shape, never the text
# somebody pasted. A link therefore cannot put an arbitrary origin in front of a visitor,
# and pasting `https://evil.example/watch?v=…` is a refused link rather than an iframe.
#
# A page carries one clip per service. That is a rule and not a nicety: a page with one
# YouTube embed is a page with a video on it, and a page with twenty is a billboard.
class StreamLink < ApplicationRecord
  MAX_TITLE_LENGTH = 80

  belongs_to :user

  # A posted thing: it can be reacted to, and written on.
  include Reactable

  normalizes :url, with: ->(value) { value.to_s.strip }
  normalizes :title, with: ->(value) { value.to_s.strip }

  validates :url, presence: true
  # Skipped when the url could not be read, because the message the owner needs is the one
  # about their link — "Platform is not included in the list" says nothing about a URL they
  # pasted that this site does not know, and reading both at once is just noise.
  validates :platform, inclusion: { in: VideoSource.keys }, unless: :url_unread?
  validates :title, length: { maximum: MAX_TITLE_LENGTH }, allow_blank: true
  validates :platform, uniqueness: { scope: :user_id, message: "is already on your page" }, unless: :url_unread?

  # Read before validating, so the platform and reference are filled in from the url and
  # the validations are judging what was actually read rather than what was typed.
  before_validation :read_url

  def embed
    StreamEmbed.for(self)
  end

  def platform_label
    VideoSource.label(platform)
  end

  # A title to show when the owner did not give one.
  def display_title
    title.presence || "#{platform_label} on @#{user.username}"
  end

  # Whether there is nothing readable here: a blank url, or one this site cannot read as a
  # video. A blank url is its own validation's business, but it also leaves the platform
  # empty, and this keeps that from being reported twice.
  def url_unread?
    url.blank? || platform.blank?
  end

  private
    def read_url
      return if url.blank?

      platform, reference = VideoSource.parse(url)

      if platform.nil?
        errors.add(:url, "must be a #{VideoSource.describe} link to a video, stream or channel")
        return
      end

      self.platform = platform
      self.reference = reference

      # A different video on the same service is a different link; the same video is the
      # same link and has no business appearing twice.
      if user && user.stream_links.where(platform: platform, reference: reference).where.not(id: id).exists?
        errors.add(:url, "is already on your page")
      end
    end
end
