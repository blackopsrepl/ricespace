# frozen_string_literal: true

require "test_helper"

# Finding a page, and taking what is on it: the directory, and lifting somebody's
# layout onto your own page.
class DirectoryTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano", greeting: "welcome")
    @other = User.create!(username: "cordelia", email_address: "c@example.com",
      password: "correct horse battery", name: "Cordelia")
  end

  test "the directory shows each page in its own colours" do
    @other.profile.update!(document: %(<style>body { background-color: #000080; color: #ff00ff }</style><p>hi</p>))

    get root_url

    assert_response :success
    assert_match "background-color: #000080", response.body
    assert_match "color: #ff00ff", response.body
    assert_match "Cordelia", response.body
  end

  test "a page that has said nothing falls back to the site's colours" do
    get root_url

    assert_response :success
    assert_match "background-color: transparent", response.body
    assert_match "color: #a1a1aa", response.body
  end

  test "the directory lists the layouts to wear" do
    get root_url

    assert_match "Layouts to wear", response.body
    assert_match "Blacklight", response.body
    assert_match "All layouts", response.body
  end

  test "taking a layout replaces the page's own rules, so the copy is what you see" do
    @other.profile.update!(document: %(<style>body { background-color: #000080 } .mine { color: red }</style>))
    @user.profile.update!(document: %(<style>body { background-color: #ffffff; color: #000000 } .mine { color: blue }</style><marquee>my page</marquee>))
    sign_in

    post copy_layout_profile_path(@other)

    @user.profile.reload
    css = @user.profile.rendered.css

    # Their look, not ours: taking a layout on a page that had styled itself would
    # otherwise be a no-op, because the page's own rules come last when a layout is worn.
    assert_includes css, "background-color: #000080"
    refute_includes css, "#ffffff"
    refute_includes css, "color: blue"
    # Their own rules come too — taking a layout is taking the whole stylesheet, which is
    # what you got when you copied a `<style>` block out of a page.
    assert_includes css, ".mine"
    # And the markup is untouched.
    assert_includes @user.profile.document, "<marquee>my page</marquee>"
  end

  test "a page with no stylesheet has nothing to take" do
    sign_in

    post copy_layout_profile_url(@other)

    assert_redirected_to profile_url(@other)
    assert_match "no stylesheet to take", flash[:alert]
    assert_equal "", @user.profile.reload.document
  end

  test "taking a layout needs a session" do
    @other.profile.update!(document: %(<style>body { background-color: #000 }</style>))

    post copy_layout_profile_url(@other)

    assert_redirected_to new_session_url
  end

  test "the offer appears on somebody else's page and not on your own" do
    @other.profile.update!(document: %(<style>body { background-color: #000 }</style>))
    sign_in

    get profile_url(@other)
    assert_match "Take this layout", response.body

    @user.profile.update!(document: %(<style>body { background-color: #fff }</style>))
    get profile_url(@user)
    refute_match "Take this layout", response.body
  end

  test "a signed-out visitor is offered a sign-in instead" do
    @other.profile.update!(document: %(<style>body { background-color: #000 }</style>))

    get profile_url(@other)

    assert_match "Sign in to take this layout", response.body
    refute_match "Take this layout", response.body
  end

  private
    def sign_in
      post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
    end
end
