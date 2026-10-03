# frozen_string_literal: true

require "test_helper"

# Videos and streams from the browser: an owner links one, a visitor sees it embedded.
class StreamLinksTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "an owner links a video and it embeds on their page" do
    post stream_links_url, params: { stream_link: {
      url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "my setup tour"
    } }

    assert_redirected_to studio_url

    get profile_url(@user)

    assert_response :success
    assert_match 'id="watch"', response.body
    assert_match "www.youtube-nocookie.com/embed/dQw4w9WgXcQ", response.body
    assert_match "my setup tour", response.body
    # The permalink is on the page as a link, which is what a reader gets when the
    # service will not frame.
    assert_match "youtube.com/watch?v=dQw4w9WgXcQ", response.body
  end

  test "a link from somewhere else is refused, and says so" do
    post stream_links_url, params: { stream_link: { url: "https://evil.example/watch?v=dQw4w9WgXcQ" } }

    assert_redirected_to studio_url
    assert_match "must be a YouTube, Vimeo, Twitch or X link", flash[:alert]
    # One message about their link, not that plus an internal one about the platform column.
    refute_match "Platform", flash[:alert]
    assert_empty @user.stream_links
  end

  test "the content security policy allows exactly the embed hosts" do
    post stream_links_url, params: { stream_link: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" } }

    get profile_url(@user)
    policy = response.headers["Content-Security-Policy"]

    assert_includes policy, "frame-src"
    EmbedHosts::ALL.each { |host| assert_includes policy, host }
    # And nothing wider: scripts are still only this site's.
    assert_includes policy, "script-src 'self'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
  end

  test "removing a link takes it off the page" do
    post stream_links_url, params: { stream_link: { url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" } }
    link = @user.stream_links.sole

    delete stream_link_url(link)

    assert_redirected_to studio_url
    get profile_url(@user)
    refute_match 'id="watch"', response.body
  end

  test "the studio lists and edits the links" do
    post stream_links_url, params: { stream_link: {
      url: "https://x.com/somebody/status/1234567890123456789", title: "a post"
    } }

    get studio_url

    assert_response :success
    assert_match "Watch", response.body
    assert_match "a post", response.body
    assert_match "Add to your page", response.body
  end

  test "a Twitch channel embeds with this host named" do
    post stream_links_url, params: { stream_link: { url: "https://www.twitch.tv/somebody" } }

    get profile_url(@user)

    assert_match "player.twitch.tv?channel=somebody", response.body
  end
end
