# frozen_string_literal: true

require "test_helper"

# Comments are signed in only, and answerable: every comment has an account behind it.
class CommentTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery")
    @friend = User.create!(username: "cordelia", email_address: "c@example.com",
      password: "correct horse battery")
  end

  test "a signed-out visitor is sent to sign in instead of commenting" do
    assert_no_difference -> { Comment.count } do
      post profile_comments_path(@owner), params: { comment: { body: "spam" } }
    end

    assert_redirected_to new_session_path
  end

  test "a signed-in account leaves a comment as itself, with no name to type" do
    sign_in_as @friend

    assert_difference -> { Comment.count } => 1 do
      post profile_comments_path(@owner), params: { comment: { body: "nice page" } }
    end

    comment = Comment.last
    assert_equal @friend, comment.author
    assert_equal "cordelia", comment.displayed_author
  end

  test "an anonymous name sent by hand is ignored" do
    sign_in_as @friend

    post profile_comments_path(@owner),
      params: { comment: { body: "hi", author_name: "somebody else" } }

    assert_equal @friend, Comment.last.author
    assert_equal "cordelia", Comment.last.displayed_author
  end

  test "a comment with no account behind it cannot be saved" do
    assert_raises(ActiveRecord::NotNullViolation) do
      Comment.new(user_id: @owner.id, body: "hi").save!(validate: false)
    end
  end

  test "the page shows a sign-in prompt instead of a comment box to a visitor" do
    get profile_path(@owner)

    assert_response :success
    assert_no_match(/id="comment-form"/, response.body)
    assert_match "to post on this wall", response.body
  end

  test "the page shows the box to a signed-in account" do
    sign_in_as @friend

    get profile_path(@owner)

    assert_match(/id="comment-form"/, response.body)
    assert_match "write on @vittorio&#39;s wall as @cordelia", response.body
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
