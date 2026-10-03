# frozen_string_literal: true

require "test_helper"

# The three things a page gained: a song, an ordered list, and layouts to wear.
class PageFeaturesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    sign_in
  end

  test "a song is saved on the page, and plays on it" do
    patch update_song_studio_url, params: { profile: {
      song_title: "Modem Handshake", song_url: "https://example.com/song.mp3",
      version: @user.profile.version
    } }

    assert_redirected_to studio_url
    @user.profile.reload
    assert_equal "https://example.com/song.mp3", @user.profile.song_url

    get profile_url(@user)

    assert_match "Modem Handshake", response.body
    assert_match %(<audio class="song" controls preload="none" src="https://example.com/song.mp3"), response.body
  end

  test "a song that is not an http address is refused" do
    [ "javascript:alert(1)", "https://example.com/s.mp3\njavascript:alert(1)", "not a url at all", "data:audio/mp3;base64,AAAA" ].each do |bad|
      patch update_song_studio_url, params: { profile: { song_url: bad, version: @user.profile.version } }

      assert_response :unprocessable_content, "expected #{bad.inspect} to be refused"
      assert_nil @user.profile.reload.song_url
    end
  end

  test "a song cannot be saved from a stale editor" do
    stale = @user.profile.version
    @user.profile.update!(document: "<p>moved on</p>")

    patch update_song_studio_url, params: { profile: { song_url: "https://example.com/s.mp3", version: stale } }

    assert_response :conflict
    assert_nil @user.profile.reload.song_url
  end

  test "a page with no song has no player" do
    get profile_url(@user)

    refute_match "audio class=\"song\"", response.body
  end

  test "friends are ordered by the owner, and the order is the page's order" do
    cordelia = create_user("cordelia")
    wes = create_user("wes")
    @user.friendships.create!(friend: cordelia)
    @user.friendships.create!(friend: wes)

    get profile_url(@user)
    assert_operator response.body.index("cordelia"), :<, response.body.index("wes")

    patch move_friendship_url(@user.friendships.in_order.last), params: { direction: "up" }
    assert_redirected_to studio_url

    get profile_url(@user)
    assert_operator response.body.index("wes"), :<, response.body.index("cordelia")
  end

  test "the first eight friends are marked as the top eight" do
    10.times { |n| @user.friendships.create!(friend: create_user("friend#{n}")) }

    get profile_url(@user)

    assert_equal 8, response.body.scan("top8-slot").size
  end

  test "the author's stylesheet reaches the page unescaped" do
    @user.profile.update!(document: %(<style>.quoted { font-family: "Courier New", monospace; color: red; }</style><p>hi</p>))

    get profile_url(@user)
    sheet = response.body[/<style[^>]*>(.*?)<\/style>/m, 1].to_s

    # Escaped quotes would make the declaration parse as something else entirely.
    assert_includes sheet, %(font-family: "Courier New")
    refute_includes sheet, "&quot;"
    assert_includes sheet, "color: red"
  end

  test "a stylesheet cannot break out of the style element" do
    @user.profile.update!(document: <<~HTML)
      <style>.quote { content: "</style><script>alert('pwned')</script>"; color: red; }</style>
      <p>hi</p>
    HTML

    get profile_url(@user)

    # The payload's own `</style>` ends the block at the HTML level, so everything
    # after it is markup for the allowlist to judge — and the allowlist prunes a
    # `<script>` together with its contents, so the payload leaves nothing behind:
    # no script element, no script text, not even an escaped copy of it.
    refute_includes response.body, "pwned"
    refute_includes response.body, "alert("
    refute_includes response.body, "<script>alert"
  end

  test "the layout preview renders the layout's stylesheet unescaped" do
    get layout_url(Layout.find("terminal"))
    sheet = response.body[/<style[^>]*>(.*?)<\/style>/m, 1].to_s

    assert_includes sheet, %(font-family: "Courier New")
    refute_includes sheet, "&quot;"
  end

  test "the layouts index lists them and a preview renders one" do
    get layouts_url

    assert_response :success
    assert_match "Blacklight", response.body

    get layout_url(Layout.find("newspaper"))

    assert_response :success
    assert_match "Newspaper", response.body
    # The layout is on the preview page as a stylesheet, over the page anatomy.
    assert_match "friendSpace", response.body
    assert_match "blurb-title", response.body
  end

  test "applying a layout writes it onto the page and keeps the markup" do
    @user.profile.update!(document: "<marquee>my page</marquee>")
    version = @user.profile.version

    post apply_layout_url(Layout.find("blacklight"))

    assert_redirected_to profile_url(@user)
    @user.profile.reload
    assert_operator @user.profile.version, :>, version
    assert_includes @user.profile.document, "<marquee>my page</marquee>"
    assert_includes @user.profile.rendered.css, "background-color: #000000"
  end

  test "a signed-out visitor is not offered the apply button" do
    delete session_url

    get layouts_url

    assert_response :success
    refute_match "Use this layout", response.body
  end

  test "applying a layout needs a session" do
    delete session_url

    post apply_layout_url(Layout.find("blacklight"))

    assert_redirected_to layouts_url
    assert_match "Sign in", flash[:alert]
  end

  private
    def sign_in
      post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
    end

    def create_user(username)
      User.create!(username: username, email_address: "#{username}@example.com", password: "correct horse battery")
    end
end
