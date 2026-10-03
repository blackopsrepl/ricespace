# frozen_string_literal: true

require "test_helper"

# The profile page's social contract: names go somewhere, friends can be made,
# the Top 8 says it, the layout action leads, and dead wiring stays out.
class ProfileUxTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    @visitor = User.create!(username: "cordelia", email_address: "c@example.com",
      password: "correct horse battery", name: "Cordelia")
    @owner.profile.update!(document: "<style>body { background: #000 }</style><p>hi</p>")
  end

  test "a comment author's name links to their page" do
    sign_in(@visitor)
    post profile_comments_path(@owner), params: { comment: { body: "nice rice" } }

    get profile_url(@owner)

    assert_response :success
    assert_select "a[href=?]", profile_path(@visitor), text: @visitor.display_name
  end

  test "a signed-in visitor is offered add-friend on someone else's page" do
    sign_in(@visitor)

    get profile_url(@owner)

    assert_response :success
    assert_select "form[action=?]", friendships_path, count: 1
    assert_match(/Add @vittorio as friend/, response.body)
    assert_no_match(/placeholder="their username"/, response.body)
  end

  test "the owner manages friends by username on their own page" do
    sign_in(@owner)

    get profile_url(@owner)

    assert_response :success
    assert_match(/placeholder="their username"/, response.body)
  end

  test "the owner is not offered to befriend themselves" do
    sign_in(@owner)

    get profile_url(@owner)

    assert_response :success
    assert_no_match(/Add @vittorio as friend/, response.body)
  end

  test "adding a friend from a profile returns to that profile" do
    sign_in(@visitor)

    post friendships_path, params: { username: @owner.username },
      headers: { "Referer" => profile_url(@owner) }

    assert_redirected_to profile_url(@owner)
    assert_includes @visitor.friendships.reload.map(&:friend), @owner
  end

  test "the friends header reads Top 8" do
    get profile_url(@owner)

    assert_response :success
    assert_match(/Top 8/i, response.body)
  end

  test "take-this-layout is the primary action on someone else's styled page" do
    sign_in(@visitor)

    get profile_url(@owner)

    assert_response :success
    node = Nokogiri::HTML(response.body).at_css("form[action*='copy_layout'] input[type='submit'], form[action*='copy_layout'] button")
    assert node, "expected a take-layout control"
    assert_match(/btn-primary/, node["class"].to_s)
  end

  test "the profile stamp follows the owner's markup" do
    get profile_url(@owner)

    body = response.body
    markup_at = body.index('id="profile"')
    stamp_at = body.index('id="profile-stamp"')
    assert markup_at && stamp_at && markup_at < stamp_at,
      "expected the stamp to follow the markup"
    tail = body[stamp_at, 2000]
    assert_no_match(/id="(watch|demos|hardware)"/, tail,
      "expected the stamp to sit with the markup, not past later sections")
  end

  test "no dead stimulus wiring on the friends section" do
    refute_match(/friends#expand/, response_body_for(@owner))
  end

  test "an empty showcase is skipped for visitors, offered to the owner" do
    get profile_url(@owner)
    assert_no_match(/id="showcase"/, response.body)

    sign_in(@owner)
    get profile_url(@owner)
    assert_match(/id="showcase"/, response.body)
    assert_match(/Build your showcase/, response.body)
  end

  test "empty markup offers the owner a CTA and shows visitors nothing" do
    blank = User.create!(username: "blank", email_address: "b@example.com",
      password: "correct horse battery", name: "Blank")

    get profile_url(blank)
    assert_no_match(/No markup yet/, response.body)

    sign_in(blank)
    get profile_url(blank)
    assert_match(/No markup yet/, response.body)
  end

  test "views count visitors, not owners; last-seen tracks the owner only" do
    before = @owner.profile.view_count

    get profile_url(@owner)
    assert_equal before + 1, @owner.profile.reload.view_count
    assert_nil @owner.reload.last_seen_at

    sign_in(@owner)
    get profile_url(@owner)
    assert_equal before + 1, @owner.profile.reload.view_count
    assert_not_nil @owner.reload.last_seen_at
  end

  private
    def sign_in(user)
      post session_url, params: { email_address: user.email_address, password: "correct horse battery" }
    end

    def response_body_for(user)
      get profile_url(user)
      response.body
    end
end
