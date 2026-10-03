# frozen_string_literal: true

require "test_helper"

# Closing your own account, and the limits on how fast an account can be made or
# signed into.
class AccountLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "cordelia", email_address: "c@example.com",
      password: "correct horse battery", name: "Cordelia")
    @user.profile.update!(document: "<h1>mine</h1>")
    @user.showcase&.destroy
    @user.create_showcase(title: "a rice")
    @user.comments.create!(author: @user, body: "note to self")
  end

  test "an owner closes their account and everything on it goes" do
    sign_in_as @user

    assert_difference -> { User.count } => -1,
      -> { Profile.count } => -1,
      -> { Showcase.count } => -1,
      -> { Comment.count } => -1 do
      delete account_path
    end

    assert_redirected_to root_path
    assert_nil User.find_by(username: "cordelia")
  end

  test "a visitor cannot close an account" do
    assert_no_difference -> { User.count } do
      delete account_path
    end

    assert_redirected_to new_session_path
  end

  test "an account that commented on somebody else's wall can still be closed" do
    # The comment it left points at its author from the other side, and nothing about
    # "the comments on my page" covers it. Without the `written_comments` association this
    # fails on a foreign key, so an account that had ever written on a wall could not be
    # closed at all — which is the worst version of this bug, because the person hitting it
    # is the one trying to leave.
    other = User.create!(username: "somebody", email_address: "s@example.com", password: "correct horse battery")
    @user.written_comments.create!(commentable: other, body: "a note on your wall")

    sign_in_as @user

    # Two comments go: the one this account wrote on their wall, and the one the setup
    # already put on this account's own page.
    assert_difference -> { User.count } => -1, -> { Comment.count } => -2 do
      delete account_path
    end

    assert_redirected_to root_path
  end

  test "a comment somebody left on a closed page's wall goes with the page" do
    commenter = User.create!(username: "commenter", email_address: "cm@example.com", password: "correct horse battery")
    commenter.written_comments.create!(commentable: @user, body: "nice page")

    sign_in_as @user

    assert_difference -> { Comment.count } => -2 do
      delete account_path
    end
  end

  test "the site's own account cannot be closed" do
    sign_in_as ron

    assert_no_difference -> { User.count } do
      delete account_path
    end

    assert_redirected_to studio_path
  end

  test "the studio offers the button to an ordinary account and not to ron" do
    sign_in_as @user
    get studio_path
    assert_match "Close this account", response.body

    delete session_path
    sign_in_as ron
    get studio_path
    assert_no_match(/Close this account/, response.body)
  end

  test "sign-in attempts from one client are limited" do
    (SessionsController::ATTEMPTS_PER_WINDOW + 1).times do
      post session_path, params: { email_address: "c@example.com", password: "wrong password entirely" }
    end

    assert_response :too_many_requests
  end

  test "sign-ups from one client are limited" do
    count_before = User.count

    (RegistrationsController::SIGN_UPS_PER_WINDOW + 3).times do |i|
      post registration_path, params: { user: {
        username: "person#{i}", email_address: "person#{i}@example.com",
        password: "correct horse battery" } }
    end

    assert_operator User.count - count_before, :<=, RegistrationsController::SIGN_UPS_PER_WINDOW
  end

  private
    # The site's own account. Find-or-create rather than a bare read because a parallel
    # test worker has its own database copy and may not have been seeded — and if it was
    # seeded, it carries the real password from a file this test cannot read, so signing
    # in as him means giving him a password this test knows.
    def ron
      @ron ||= as_test_account(User.ron || User.create!(username: User::RON,
        email_address: "ron@ricespace.example", password: TEST_PASSWORD, admin: true))
    end

    # Signing in is rate limited by client, so a test that signs in several times in one
    # run runs into its own limit — the counter is per IP and every request here comes
    # from the same one. Clearing the store keeps these tests about the account rather
    # than about the limit, which has its own test below. `bin/ci` hides this by running
    # the suite in parallel, which is why it only shows up when the file runs alone.
    def sign_in_as(user)
      ApplicationController::RATE_LIMIT_STORE.clear

      post session_path, params: { email_address: user.email_address, password: TEST_PASSWORD }
    end

    # A password these tests can sign in with. The seeded Ron carries a real password
    # read from a file outside the app — deliberately, since the repository is public —
    # so a test cannot know it and cannot sign in as him as seeded.
    TEST_PASSWORD = "correct horse battery"

    def as_test_account(user)
      user.update!(password: TEST_PASSWORD, password_confirmation: TEST_PASSWORD)
      user
    end
end
