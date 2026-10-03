# frozen_string_literal: true

require "test_helper"

class StreamLinkTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
  end

  def link(url, title: nil)
    @user.stream_links.build(url: url, title: title)
  end

  test "the links people actually paste are read" do
    {
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ" => [ "youtube", "dQw4w9WgXcQ" ],
      "https://youtu.be/dQw4w9WgXcQ" => [ "youtube", "dQw4w9WgXcQ" ],
      "https://youtube.com/shorts/dQw4w9WgXcQ" => [ "youtube", "dQw4w9WgXcQ" ],
      "https://m.youtube.com/watch?v=dQw4w9WgXcQ&t=30s" => [ "youtube", "dQw4w9WgXcQ" ],
      "https://www.youtube.com/live/dQw4w9WgXcQ" => [ "youtube", "dQw4w9WgXcQ" ],
      "https://www.twitch.tv/videos/1234567890" => [ "twitch", "1234567890" ],
      "https://twitch.tv/somebody" => [ "twitch", "somebody" ],
      "https://vimeo.com/123456789" => [ "vimeo", "123456789" ],
      "https://player.vimeo.com/video/123456789" => [ "vimeo", "123456789" ],
      "https://www.x.com/somebody/status/1234567890123456789" => [ "x", "1234567890123456789" ],
      "https://twitter.com/somebody/status/1234567890123456789" => [ "x", "1234567890123456789" ]
    }.each do |url, (platform, reference)|
      record = link(url)

      assert record.valid?, "expected #{url} to be accepted, got #{record.errors.full_messages.inspect}"
      assert_equal platform, record.platform
      assert_equal reference, record.reference
    end
  end

  test "a link from anywhere else is refused" do
    [
      "https://evil.example/watch?v=dQw4w9WgXcQ",
      "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
      "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
      "javascript:alert(1)",
      "data:text/html,<iframe src=//evil>",
      "not a url at all",
      "https://youtube.com/",
      "https://youtube.com/results?search_query=cats",
      "https://user:password@youtube.com/watch?v=dQw4w9WgXcQ",
      "https://vimeo.com/channels/staffpicks"
    ].each do |url|
      record = link(url)

      refute record.valid?, "expected #{url} to be refused"
      assert record.errors[:url].any?
    end
  end

  test "the platform is read from the url, never supplied" do
    record = link("https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    assert record.valid?
    # Even if a platform were posted, the url is what decides — it is re-read on every
    # validation, so a supplied value cannot survive.
    record.platform = "twitch"
    record.reference = "somebody"
    record.valid?

    assert_equal "youtube", record.platform
    assert_equal "dQw4w9WgXcQ", record.reference
  end

  test "one clip per service, and the same video twice is refused" do
    assert link("https://www.youtube.com/watch?v=dQw4w9WgXcQ").save

    assert_not link("https://youtu.be/dQw4w9WgXcQ").valid?
    refute link("https://www.youtube.com/watch?v=dQw4w9WgXcQ").valid?
  end

  test "a different video on the same service still needs the platform free" do
    assert link("https://www.youtube.com/watch?v=dQw4w9WgXcQ").save

    record = link("https://www.youtube.com/watch?v=aaaaaaaaaaa")

    refute_predicate record, :valid?
    assert_match "already on your page", record.errors[:platform].to_s
  end

  test "deleting the account takes its links" do
    link("https://www.youtube.com/watch?v=dQw4w9WgXcQ").save!

    assert_difference -> { StreamLink.count } => -1 do
      @user.destroy
    end
  end

  test "the database refuses a second link for one service" do
    link("https://www.youtube.com/watch?v=dQw4w9WgXcQ").save!

    assert_raises(ActiveRecord::RecordNotUnique) do
      @user.stream_links.new(url: "https://youtu.be/aaaaaaaaaaa", platform: "youtube", reference: "aaaaaaaaaaa")
        .save!(validate: false)
    end
  end
end
