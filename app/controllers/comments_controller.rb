# frozen_string_literal: true

# Writing on something somebody posted.
#
# Signed in only: an account writes as itself, and the post's owner or the comment's own
# author can remove what was written.
#
# A post is somebody's front door, and a box on it that anyone can write into anonymously is
# a spam target with no accountable author — the account is what makes a comment answerable.
#
# What is written on is named by a kind and an id, so the same box serves a page, the rice, a
# shot of it, a build, a demo or a link. No kind given means the page, which is what every
# existing form sends.
class CommentsController < ApplicationController
  before_action :require_authentication, only: [ :create ]

  # The kinds that can be written on, by the name the page sends. The same list the reactions
  # use: what can be reacted to is what can be answered, and keeping one list means the two
  # cannot drift apart.
  TARGETS = RatingsController::TARGETS

  def create
    page = User.find_by!(username: params[:username])
    thing = target(page)

    if thing.nil?
      return redirect_to profile_path(page, anchor: "comments"), alert: "There is no such post."
    end

    comment = thing.comments.build(body: params.require(:comment).permit(:body)[:body])
    comment.author = current_user

    if comment.save
      redirect_to profile_path(page, anchor: anchor_for(thing)), notice: "Comment left."
    else
      redirect_to profile_path(page, anchor: anchor_for(thing)),
        alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    comment = Comment.find(params[:id])
    owner = comment.owner

    if signed_in? && (current_user == owner || current_user == comment.author)
      comment.destroy!
      redirect_to profile_path(owner, anchor: "comments"), notice: "Comment removed."
    else
      redirect_to profile_path(owner, anchor: "comments"),
        alert: "That comment is not yours to remove."
    end
  end

  private
    # What is being written on. No kind given means the page itself.
    def target(page)
      kind = params[:kind].presence
      return page if kind.nil?

      klass = TARGETS[kind]
      return nil if klass.nil?

      thing = klass.constantize.find_by(id: params[:id])
      return nil if thing.nil?

      owner = thing.respond_to?(:owner) ? thing.owner : nil
      return nil unless owner&.id == page.id

      thing
    end

    # Back to the wall that was written on, so a comment on the rice leaves you looking at
    # the rice rather than at the top of the page.
    def anchor_for(thing)
      return "comments" if thing.is_a?(User)

      params[:anchor].presence || thing.class.name.underscore
    end
end
