# frozen_string_literal: true

require "test_helper"

# The embed builder is the only thing in the application that writes an off-site URL into
# a frame, so it gets its own tests: what it emits, and what it refuses to emit.
class StreamEmbedTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
  end

  def embed(url, title: nil, user: nil)
    link = (user || @user).stream_links.create!(url: url, title: title)
    StreamEmbed.for(link)
  end

  test "a YouTube video embeds from the no-cookie player, by id" do
    frame = embed("https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "a video")

    assert_equal "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", frame[:src]
    assert_equal "a video", frame[:title]
    assert_equal "16 / 9", frame[:aspect]
  end

  test "a Twitch video and a Twitch channel embed differently, and name this host" do
    # One Twitch link per page, so the two forms are exercised on two accounts.
    other = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")

    video = embed("https://www.twitch.tv/videos/1234567890")
    channel = embed("https://www.twitch.tv/somebody", user: other)

    assert_includes video[:src], "video=1234567890"
    assert_includes channel[:src], "channel=somebody"
    assert_includes video[:src], "parent="
    assert_includes channel[:src], "parent="
  end

  test "an X post embeds as a card" do
    frame = embed("https://x.com/somebody/status/1234567890123456789")

    assert_equal "https://platform.twitter.com/tweetembed/1234567890123456789", frame[:src]
    assert_equal "auto", frame[:aspect]
  end

  test "the embed's host is chosen by the builder, not taken from the link" do
    frame = embed("https://youtu.be/dQw4w9WgXcQ")

    assert_equal "www.youtube-nocookie.com", URI.parse(frame[:src]).host
    refute_includes frame[:src], "youtu.be"
  end

  test "a reference that is not the platform's shape produces no embed rather than a frame" do
    link = @user.stream_links.create!(url: "https://youtu.be/dQw4w9WgXcQ")
    # Simulate a reference that reached the column by some other route.
    link.update_column(:reference, "not-an-id/../../evil")

    assert_nil link.embed
  end

  test "an unknown platform produces no embed" do
    link = @user.stream_links.create!(url: "https://youtu.be/dQw4w9WgXcQ")
    link.update_column(:platform, "myspace")

    assert_nil link.embed
  end

  test "the allowed frame hosts are the services, and nothing else" do
    assert_equal [ "platform.twitter.com", "player.twitch.tv", "player.vimeo.com", "www.youtube-nocookie.com" ],
      EmbedHosts::ALL.sort
    assert_equal EmbedHosts::ALL.sort,
      [ "youtube", "vimeo", "twitch", "x" ].map { |platform| URI.parse(StreamEmbed::BASES[platform]).host }.sort
  end

  test "a Vimeo video embeds from the Vimeo player" do
    frame = embed("https://vimeo.com/123456789")

    assert_equal "https://player.vimeo.com/video/123456789", frame[:src]
  end

  test "a demo's link becomes an embed when it is a video, and nothing when it is a catalogue page" do
    video = StreamEmbed.for_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "a demo")
    catalogue = StreamEmbed.for_url("https://www.pouet.net/prod.php?which=12345", title: "a demo")

    assert_equal "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", video[:src]
    assert_equal "a demo", video[:title]
    assert_nil catalogue
  end
end
