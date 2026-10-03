# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "a new account gets an empty profile" do
    user = create_user

    assert_predicate user.profile, :persisted?
    assert_equal "", user.profile.document
  end

  test "deleting an account takes the profile and its tokens with it" do
    user = create_user
    AgentToken.issue(user: user, name: "claude code")

    assert_difference -> { Profile.count } => -1, -> { AgentToken.count } => -1 do
      user.destroy
    end
  end

  test "email is folded to one case so an address cannot have two accounts" do
    create_user(email_address: "Vittorio@Example.com", username: "vittorio")

    duplicate = User.new(email_address: "vittorio@example.com", username: "other", password: "correct horse battery")

    refute_predicate duplicate, :valid?
    assert duplicate.errors[:email_address].any?
  end

  test "usernames are lowercased, URL-safe and unique" do
    user = create_user(username: "Vittorio")

    assert_equal "vittorio", user.username
    assert_equal "vittorio", user.to_param

    %w[no spaces! -leading trailing- a.b a_b ab_c].each do |bad|
      assert_not User.new(email_address: "x@example.com", username: bad, password: "correct horse battery").valid?,
        "expected #{bad.inspect} to be refused"
    end
  end

  test "names the site might need are reserved" do
    assert_not User.new(email_address: "a@example.com", username: "admin", password: "correct horse battery").valid?
    assert_not User.new(email_address: "a@example.com", username: "profiles", password: "correct horse battery").valid?
  end

  test "an account needs a password long enough to be worth typing" do
    short = User.new(email_address: "a@example.com", username: "someone", password: "short")

    refute_predicate short, :valid?
    assert short.errors[:password].any?
  end

  test "display name prefers the chosen name and falls back to the username" do
    assert_equal "Vittorio Distefano", create_user(username: "vittorio", name: "Vittorio Distefano").display_name
    assert_equal "cordelia", create_user(username: "cordelia", name: nil, email_address: "c@example.com").display_name
  end

  test "an account with no username or email is not valid" do
    assert_not User.new.valid?
  end

  private
    def create_user(username: "vittorio", name: "Vittorio Distefano",
                    email_address: "vittorio@example.com", password: "correct horse battery")
      User.create!(
        username: username, name: name, email_address: email_address, password: password
      )
    end
end
