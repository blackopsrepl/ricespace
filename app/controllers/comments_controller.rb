# frozen_string_literal: true

# Comments left on a page. The owner of the page can remove one; anybody signed in
# can leave one, and a signed-out visitor can leave one under a name they type.
class CommentsController < ApplicationController
  def create
    user = User.find_by!(username: params[:username])
    comment = user.comments.build(comment_params)
    comment.author = current_user if signed_in?

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

  private
    def comment_params
      params.require(:comment).permit(:body, :author_name)
    end
end
