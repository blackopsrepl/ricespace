# frozen_string_literal: true

# A profile page as a visitor sees it: the site's own chrome, then the page itself
# — markup and the author's stylesheet, cleaned on render. Profiles are looked up
# by username so the URL is the one the owner hands out.
#
# The page has an anatomy: a picture, a friends list, blurbs, comments. Every one
# of those is rendered with the id and class a layout from the era targets
# (`.contactTable`, `.friendSpace`, `.blurb`, `.comments`, `.profile-pic`), which
# is what makes a pasted stylesheet land on something.
class ProfilesController < ApplicationController
  before_action :require_authentication, only: [ :update_picture, :destroy_picture ]

  # How many friends a page lists, and how many comments it shows.
  TOP_FRIENDS = 12
  COMMENTS_SHOWN = 20

  def show
    @user = User.find_by!(username: params[:username])
    @profile = @user.profile
    @rendered = @profile.rendered
    @picture = @user.profile_picture
    @friends = @user.friends.order(:username).limit(TOP_FRIENDS)
    @friend_count = @user.friendships.count
    @blurbs = @user.blurbs.in_order
    @comments = @user.comments.includes(:author).recent_first.limit(COMMENTS_SHOWN)
    @comment = Comment.new
    @can_edit = signed_in? && current_user == @user
  end

  def update_picture
    picture = current_user.profile_picture || current_user.build_profile_picture
    picture.image.attach(params.require(:profile_picture).require(:image))
    picture.save!

    redirect_to studio_path, notice: "Profile picture updated."
  rescue ActionController::ParameterMissing => error
    redirect_to studio_path, alert: error.message
  rescue ActiveRecord::RecordInvalid => error
    redirect_to studio_path, alert: error.record.errors.full_messages.to_sentence
  end

  def destroy_picture
    current_user.profile_picture&.destroy!

    redirect_to studio_path, notice: "Profile picture removed."
  end
end
