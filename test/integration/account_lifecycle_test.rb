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
    # The site's own account, which the seed creates. Find-or-create rather than a
    # bare read because a parallel test worker has its own database copy and may not
    # have been seeded.
    def ron
      @ron ||= User.ron || User.create!(username: User::RON, email_address: "ron@ricespace.example",
        password: "correct horse battery", admin: true)
    end

    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
