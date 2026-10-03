# frozen_string_literal: true

# Reading a video URL: which service it is on, and which video.
#
# This is the security-relevant half of embedding, so it lives in one place. Both the
# links a page carries (StreamLink) and the demos it lists (Demo) go through it, and
# nothing else in the application is allowed to decide what a pasted URL means.
#
# Two things it will not do:
#
# - It never judges by the text of a URL. A link is parsed, its host must be one of the
#   hosts listed here, and the video id must match that service's own shape. `read`
#   returning nil is a refusal, and a refusal means no embed is built.
# - It does not carry an embed address. Those are in EmbedHosts, so the content security
#   policy and the iframe that is actually written agree by construction.
module VideoSource
  SOURCES = {
    "youtube" => {
      label: "YouTube",
      hosts: %w[ youtube.com www.youtube.com m.youtube.com music.youtube.com youtu.be www.youtu.be ],
      shapes: [ /\A[A-Za-z0-9_-]{11}\z/ ],
      read: lambda { |uri|
        if uri.path == "/watch"
          value = URI.decode_www_form(uri.query.to_s).to_h["v"]
          value if value&.match?(/\A[A-Za-z0-9_-]{11}\z/)
        else
          # /embed/ID, /live/ID, /shorts/ID, or youtu.be/ID
          uri.path[%r{\A/(?:embed|live|shorts|v)/([A-Za-z0-9_-]{11})/?\z}, 1] ||
            uri.path[%r{\A/([A-Za-z0-9_-]{11})/?\z}, 1]
        end
      }
    },
    "vimeo" => {
      label: "Vimeo",
      hosts: %w[ vimeo.com www.vimeo.com player.vimeo.com ],
      shapes: [ /\A\d{6,12}\z/ ],
      read: lambda { |uri|
        uri.path[%r{\A/(?:video/)?(\d{6,12})/?\z}, 1]
      }
    },
    "twitch" => {
      label: "Twitch",
      hosts: %w[ twitch.tv www.twitch.tv m.twitch.tv ],
      # A video id and a channel name: two different shapes, and two different embeds.
      shapes: [ /\A\d{6,20}\z/, /\A[A-Za-z0-9_]{3,25}\z/ ],
      read: lambda { |uri|
        uri.path[%r{\A/videos/(\d{6,20})/?\z}, 1] ||
          uri.path[%r{\A/([A-Za-z0-9_]{3,25})/?\z}, 1]
      }
    },
    "x" => {
      label: "X",
      hosts: %w[ x.com www.x.com twitter.com www.twitter.com mobile.twitter.com ],
      shapes: [ /\A\d{6,25}\z/ ],
      read: lambda { |uri|
        uri.path[%r{\A/[A-Za-z0-9_]{1,15}/status/(\d{6,25})/?\z}, 1]
      }
    }
  }.freeze

  def self.keys
    SOURCES.keys
  end

  def self.label(key)
    SOURCES.dig(key, :label) || key.to_s
  end

  def self.shapes(key)
    SOURCES.dig(key, :shapes) || []
  end

  # [platform, reference] for a URL on one of these services, or nil. Nil covers every
  # refusal: another host, a URL that will not parse, credentials in the URL, a link that
  # names no video.
  def self.parse(url)
    uri = begin
      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      nil
    end

    return if uri.nil?
    return unless %w[ http https ].include?(uri.scheme)
    return if uri.host.blank?
    # A URL carrying credentials would be a password in a column, and nothing here
    # needs one.
    return if uri.userinfo.present?

    source = SOURCES.find { |_key, spec| spec[:hosts].include?(uri.host.downcase) }
    return if source.nil?

    key, spec = source
    reference = spec[:read].call(uri)
    return if reference.blank?
    return unless spec[:shapes].any? { |shape| reference.match?(shape) }

    [ key, reference ]
  end

  # A human sentence for a refusal, used where the owner has to be told why.
  def self.describe
    keys.map { |key| label(key) }.to_sentence(last_word_connector: " or ")
  end
end
