# frozen_string_literal: true

require "test_helper"

# Linking a local account to its P2P feed: a valid key sticks, anything else
# is refused, and clearing it returns the account to local-only.
class FeedLinkingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "linker", email_address: "linker@example.com",
      password: "correct horse battery")
    @key = "a" * 64
    @other = User.create!(username: "other", email_address: "other@example.com",
      password: "correct horse battery", pubkey: "b" * 64)
  end

  test "linking a feed stores the key and creates the peer row" do
    sign_in_as @user

    patch link_feed_account_path, params: { user: { pubkey: @key } }

    assert_redirected_to studio_path
    assert_equal @key, @user.reload.pubkey
    assert Peer.find_by(pubkey: @key)&.self_feed?
  end

  test "a malformed key is refused and nothing changes" do
    sign_in_as @user

    patch link_feed_account_path, params: { user: { pubkey: "not-a-key" } }

    assert_redirected_to studio_path
    assert_nil @user.reload.pubkey
    assert_nil Peer.find_by(pubkey: "not-a-key")
  end

  test "clearing the key unlinks back to local-only" do
    @user.update!(pubkey: @key)
    sign_in_as @user

    patch link_feed_account_path, params: { user: { pubkey: "" } }

    assert_redirected_to studio_path
    assert_nil @user.reload.pubkey
  end

  test "two accounts cannot claim the same feed" do
    sign_in_as @user

    patch link_feed_account_path, params: { user: { pubkey: "b" * 64 } }

    assert_redirected_to studio_path
    assert_nil @user.reload.pubkey
  end

  private

  def sign_in_as(user)
    ApplicationController::RATE_LIMIT_STORE.clear
    post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
  end
end
