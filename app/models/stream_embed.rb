# frozen_string_literal: true

# The iframe for a video.
#
# This exists as its own object because it is the one place in the application that writes
# a URL into a `src` that points off the site, and that deserves to be small, readable and
# tested on its own.
#
# Two rules make it safe:
#
# 1. The host is chosen here, from a literal, by platform. It is never taken from the
#    link's url — that is only ever read for an id.
# 2. The id is re-checked here against the platform's own shape, so a reference that
#    somehow reached a column without passing VideoSource still cannot produce an embed.
#
# A third rule is that this returns nil rather than raising: something that cannot be
# embedded is shown as a link. A page is never broken by one.
class StreamEmbed
  # Where each service's embed is served from. The hostnames are the same list the
  # content security policy allows — see config/initializers/00_embed_hosts.rb. The names
  # are literals, deliberately: an author's paste never reaches this map.
  BASES = {
    "youtube" => "https://#{EmbedHosts::YOUTUBE}",
    "vimeo" => "https://#{EmbedHosts::VIMEO}",
    "twitch" => "https://#{EmbedHosts::TWITCH}",
    "x" => "https://#{EmbedHosts::X}"
  }.freeze

  # Build an embed from what was read out of a URL, or nil.
  def self.build(platform:, reference:, title: nil, permalink: nil)
    reference = reference.to_s
    return unless platform.present?
    return unless VideoSource.shapes(platform).any? { |shape| reference.match?(shape) }

    case platform
    when "youtube"
      frame("#{BASES["youtube"]}/embed/#{reference}", "16 / 9", platform, title, permalink)
    when "vimeo"
      frame("#{BASES["vimeo"]}/video/#{reference}", "16 / 9", platform, title, permalink)
    when "twitch"
      # A Twitch reference is a video id or a channel name, and they embed differently.
      # The shape is what says which — never a prefix somebody typed.
      if reference.match?(VideoSource.shapes("twitch").first)
        frame("#{BASES["twitch"]}?video=#{reference}&parent=#{parent_host}", "16 / 9", platform, title, permalink)
      elsif reference.match?(VideoSource.shapes("twitch").last)
        frame("#{BASES["twitch"]}?channel=#{reference}&parent=#{parent_host}", "16 / 9", platform, title, permalink)
      end
    when "x"
      # X's embed is a small card rather than a player, and sizes its own height.
      frame("#{BASES["x"]}/tweetembed/#{reference}", "auto", platform, title, permalink)
    end
  end

  # The embed for a stored link.
  def self.for(link)
    build(platform: link.platform, reference: link.reference, title: link.display_title,
      permalink: link.url)
  end

  # The embed for any URL that VideoSource can read, or nil. Used by the demos, which
  # keep a URL rather than a parsed reference — a demo's link may also be a catalogue
  # page, and that is not a video at all.
  def self.for_url(url, title: nil)
    platform, reference = VideoSource.parse(url)
    return if platform.nil?

    build(platform: platform, reference: reference, title: title, permalink: url)
  end

  def self.parent_host
    host = Rails.application.routes.default_url_options[:host].presence ||
      Rails.application.config.action_controller.default_url_options&.dig(:host)
    host || "localhost"
  end

  def self.frame(src, aspect, platform, title, permalink)
    {
      src: src,
      aspect: aspect,
      platform: VideoSource.label(platform),
      title: title,
      permalink: permalink
    }
  end

  private_class_method :frame, :parent_host
end
