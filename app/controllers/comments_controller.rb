# frozen_string_literal: true

# Comments left on a page. Signed in only: an account leaves one as itself, and the
# page's owner or the comment's own author can remove it.
#
# A page is somebody's front door, and a box on it that anyone can write into
# anonymously is a spam target with no accountable author — the account is what makes
# the comment answerable.
class CommentsController < ApplicationController
  before_action :require_authentication, only: [ :create ]

  def create
    user = User.find_by!(username: params[:username])
    comment = user.comments.build(body: params.require(:comment).permit(:body)[:body])
    comment.author = current_user

    if comment.save
      redirect_to profile_path(user, anchor: "comments"), notice: "Comment left."
    else
      redirect_to profile_path(user, anchor: "comment-form"), alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    comment = Comment.find(params[:id])
    owner = comment.user

    if signed_in? && (current_user == owner || current_user == comment.author)
      comment.destroy!
      redirect_to profile_path(owner, anchor: "comments"), notice: "Comment removed."
    else
      redirect_to profile_path(owner, anchor: "comments"), alert: "That comment is not yours to remove."
    end
  end
end
