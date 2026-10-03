# Be sure to restart your server when you modify this file.

# The hosts a page is allowed to frame, in one place.
#
# A video or stream link is embedded from the service that hosts it; this site stores no
# video. That makes framing the one thing a page can do that the sanitiser cannot decide
# — so the list lives here, as three literals, and is the single source for both the
# embed builder (which builds the src) and the content security policy (which allows it).
# An author's paste never reaches this list: the builder picks the host by platform and
# only ever reads an id out of the link.
module EmbedHosts
  YOUTUBE = "www.youtube-nocookie.com"
  VIMEO = "player.vimeo.com"
  TWITCH = "player.twitch.tv"
  X = "platform.twitter.com"

  ALL = [ YOUTUBE, VIMEO, TWITCH, X ].freeze
end
