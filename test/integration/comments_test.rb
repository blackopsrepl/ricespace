# frozen_string_literal: true

require "test_helper"

# Writing on what somebody posted.
#
# Comments are signed in only, and answerable: every comment has an account behind it. The
# second half is the change — a comment can be left on the rice, a build, a demo, rather than
# only on the page, so an answer lands where the thing it answers is.
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
      Comment.new(commentable: @owner, body: "hi").save!(validate: false)
    end
  end

  test "the page shows a sign-in prompt instead of a comment box to a visitor" do
    get profile_path(@owner)

    assert_response :success
    assert_no_match(/comments-form/, response.body)
    assert_match "to write on this", response.body
  end

  test "the page shows the box to a signed-in account" do
    sign_in_as @friend

    get profile_path(@owner)

    assert_match(/comments-form/, response.body)
    assert_match "write on this as @cordelia", response.body
  end

  # ── writing on what was posted, not only on the page ─────────────────────────────────────

  test "an account can write on somebody's rice, and it lands on the rice" do
    rice = @owner.create_showcase!(title: "my desk")
    sign_in_as @friend

    assert_difference -> { Comment.count } => 1 do
      post profile_post_comments_path(@owner, "showcase", rice.id),
        params: { comment: { body: "what is the wallpaper" } }
    end

    assert_equal rice, Comment.last.commentable, "the comment answers the rice, not the page"
    assert_equal 1, rice.comments.count
    assert_equal 0, @owner.comments.count, "and it is not also on the page's wall"
  end

  test "writing on somebody else's post on this page is refused" do
    rice = @owner.create_showcase!(title: "my desk")
    elsewhere = User.create!(username: "somebody", email_address: "s@example.com",
      password: "correct horse battery")
    other_rice = elsewhere.create_showcase!(title: "not this page")
    sign_in_as @friend

    assert_no_difference -> { Comment.count } do
      post profile_post_comments_path(@owner, "showcase", other_rice.id),
        params: { comment: { body: "wrong page" } }
    end

    assert_redirected_to profile_path(@owner, anchor: "comments")
  end

  test "the page's own wall and a post's wall are separate" do
    rice = @owner.create_showcase!(title: "my desk")
    sign_in_as @friend

    post profile_comments_path(@owner), params: { comment: { body: "on the page" } }
    post profile_post_comments_path(@owner, "showcase", rice.id),
      params: { comment: { body: "on the rice" } }

    assert_equal [ "on the page" ], @owner.wall.map(&:body)
    assert_equal [ "on the rice" ], rice.wall.map(&:body)
  end

  test "the owner of the post can remove a comment somebody left on it" do
    rice = @owner.create_showcase!(title: "my desk")
    comment = rice.comments.create!(author: @friend, body: "not this")
    sign_in_as @owner

    assert_difference -> { Comment.count } => -1 do
      delete comment_path(comment)
    end
  end

  private
    def sign_in_as(user)
      post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
