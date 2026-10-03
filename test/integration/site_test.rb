# frozen_string_literal: true

require "test_helper"

# The browser flows: what an owner does, and what a visitor sees.
class SiteTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "vittorio@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
  end

  test "the front page greets a visitor and lists the pages that exist" do
    get root_url

    assert_response :success
    assert_match "on a page you wrote yourself", response.body

    @user.profile.update!(document: %(<h1 style="color:#ff00ff">vittorio</h1>))
    get root_url

    assert_match "Vittorio Distefano", response.body
    assert_match "changed", response.body
  end

  test "creating a page signs the owner in and lands them in the studio" do
    assert_difference -> { User.count } => 1, -> { Profile.count } => 1 do
      post registration_url, params: { user: {
        username: "cordelia", name: "Cordelia", email_address: "cordelia@example.com",
        password: "correct horse battery"
      } }
    end

    assert_redirected_to studio_url
    follow_redirect!
    assert_match "Signed in as", response.body
    assert_match "@cordelia", response.body
    assert_equal 0, User.find_by(username: "cordelia").profile.document.length
  end

  test "a refused sign-up says why and keeps what was typed" do
    post registration_url, params: { user: {
      username: "Admin", name: "Admin", email_address: "nope", password: "short"
    } }

    assert_response :unprocessable_content
    assert_match "Username is reserved", response.body
    assert_match "Email address is invalid", response.body
    assert_match "Password is too short", response.body
    assert_match %(value="Admin"), response.body
    assert_match %(value="nope"), response.body
  end

  test "signing in and out" do
    get studio_url
    assert_redirected_to new_session_url

    post session_url, params: { email_address: "Vittorio@Example.com", password: "wrong password here" }
    assert_response :unauthorized
    assert_match "do not match", response.body

    post session_url, params: { email_address: "Vittorio@Example.com", password: "correct horse battery" }
    assert_redirected_to studio_url

    delete session_url
    assert_redirected_to root_url

    get studio_url
    assert_redirected_to new_session_url
  end

  test "the studio saves the page" do
    sign_in

    patch studio_url, params: { profile: { document: %(<marquee>hello</marquee>), version: @user.profile.version } }

    assert_redirected_to studio_url
    assert_equal %(<marquee>hello</marquee>), @user.profile.reload.document
  end

  test "the studio refuses a page over the stored limit and says why" do
    sign_in

    patch studio_url, params: { profile: { document: "x" * (Profile::MAX_DOCUMENT_LENGTH + 1) } }

    assert_response :unprocessable_content
    assert_match "Document is too long", response.body
    assert_equal "", @user.profile.reload.document
  end

  test "the studio says so when it refuses a save built on a replaced page" do
    sign_in
    page = @user.profile
    page.update!(document: "<p>as saved</p>")
    stale = page.version

    # Somebody else — the owner's agent, over the API — replaces the page.
    @user.profile.update!(document: "<p>by the agent</p>")

    patch studio_url, params: { profile: { document: "<p>by hand</p>", version: stale } }

    assert_response :conflict
    assert_match "Somebody — most likely your own agent — wrote this page", response.body
    # What the owner typed is handed back in the editor, not dropped.
    assert_includes response.body, "by hand"
    assert_includes @user.profile.reload.document, "by the agent"
  end

  test "saving again after a conflict replaces the agent's version" do
    sign_in
    page = @user.profile
    page.update!(document: "<p>as saved</p>")
    stale = page.version
    @user.profile.update!(document: "<p>by the agent</p>")

    patch studio_url, params: { profile: { document: "<p>by hand</p>", version: stale } }
    patch studio_url, params: { profile: { document: "<p>by hand</p>", version: @user.profile.reload.version } }

    assert_redirected_to studio_url
    assert_includes @user.profile.reload.document, "by hand"
  end

  test "a profile page shows the author's page: markup and a stylesheet that can restyle the whole thing" do
    @user.profile.update!(document: <<~HTML)
      <style>
        body { background: #000 url(https://example.com/tile.gif) fixed }
        .main { position: absolute; left: 50%; top: 130px; margin-left: -400px; z-index: 3 }
        .orangetext15 { visibility: hidden }
      </style>
      <div class="main">
        <h1 style="color:#ff00ff">vittorio</h1>
        <marquee behavior="alternate"><font color="red">welcome</font></marquee>
        <img src="https://example.com/me.gif" onerror="alert('pwned')">
        <script>document.title = "pwned"</script>
        <a href="javascript:alert(1)">link</a>
      </div>
    HTML

    get profile_url(@user)

    assert_response :success

    # The author's sheet is on the page as a sheet, not as content inside the page's
    # markup element, and it says what the author asked for.
    sheet = response.body[/<style>(.*?)<\/style>/m, 1].to_s
    assert_includes sheet, "position: absolute"
    assert_includes sheet, "z-index: 3"
    assert_includes sheet, "visibility: hidden"
    assert_includes sheet, "url(https://example.com/tile.gif)"

    markup = response.body.split(%(<article id="profile")).last

    assert_includes markup, "<marquee"
    assert_includes markup, "color: #ff00ff"
    assert_includes markup, %(src="https://example.com/me.gif")
    refute_includes markup, "pwned"
    refute_includes markup, "javascript:"
    refute_includes markup, "<script"
  end

  test "a profile page is served with a content security policy that forbids scripts and framing" do
    get profile_url(@user)

    policy = response.headers["Content-Security-Policy"]

    assert_includes policy, "default-src 'self'"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
    refute_includes policy, "unsafe-eval"
  end

  test "a profile with no page hides the empty state from visitors" do
    get profile_url(@user)

    assert_no_match "No markup yet", response.body
  end

  test "a profile with no page offers the owner a CTA" do
    sign_in
    get profile_url(@user)

    assert_match "No markup yet", response.body
  end

  test "an unknown username is not found" do
    get profile_url("nobody")

    assert_response :not_found
  end

  test "issuing an agent token shows it once and then never again" do
    sign_in

    post agent_tokens_url, params: { agent_token: { name: "Claude Code" } }
    assert_redirected_to studio_url

    shown = flash[:agent_token]
    assert_match AgentToken::TOKEN_FORMAT, shown

    follow_redirect!
    assert_includes response.body, shown

    get studio_url
    assert_match "Claude Code", response.body
    refute_includes response.body, shown
  end

  test "revoking an agent token stops it working" do
    token = AgentToken.issue(user: @user, name: "Claude Code")
    sign_in

    delete agent_token_url(token)

    assert_redirected_to studio_url
    assert_nil AgentToken.find_by(id: token.id)

    get api_v1_profile_url, headers: { "Authorization" => "Bearer #{token.plaintext}" }
    assert_response :unauthorized
  end

  test "the agent contract is served as markdown for an agent to fetch" do
    get agents_markdown_url

    assert_response :success
    assert_includes response.media_type, "text/markdown"
    assert_match "PATCH /api/v1/profile", response.body
    assert_match "stale_document", response.body
  end

  test "the agent contract is also readable as a page" do
    get agents_url

    assert_response :success
    assert_match "agent contract", response.body
  end

  private
    def sign_in
      post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
    end
end
