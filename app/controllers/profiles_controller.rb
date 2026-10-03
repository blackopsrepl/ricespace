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
  before_action :require_authentication, only: [ :update_picture, :destroy_picture, :copy_layout ]

  # How many friends a page lists, and how many comments it shows.
  TOP_FRIENDS = 24
  COMMENTS_SHOWN = 20

  # The first eight are the ones the page shows first — the owner's order, which is
  # what made the list worth ordering at all.
  TOP_EIGHT = 8

  def show
    @user = User.find_by!(username: params[:username])
    @profile = @user.profile
    @rendered = @profile.rendered
    @picture = @user.profile_picture
    # The showcase, which is the main event on this page rather than one section of it.
    @showcase = @user.showcase
    @friends = @user.friendships.in_order.includes(:friend).map(&:friend).first(TOP_FRIENDS)
    @friend_count = @user.friendships.count
    @blurbs = @user.blurbs.in_order
    @comments = @user.comments.includes(:author).recent_first.limit(COMMENTS_SHOWN)
    # The videos and streams, which are links to somebody else's service.
    @stream_links = @user.stream_links.order(:created_at)
    # The demoscene demos, which are their own category: the release facts are the entry.
    @demos = @user.demos.in_order
    @comment = Comment.new
    @can_edit = signed_in? && current_user == @user
  end

  # Take the layout off somebody else's page onto your own.
  #
  # This is how layouts actually spread the first time round: you found a page you
  # liked, copied its stylesheet, and pasted it into yours. What travels is the
  # stylesheet in full — including whatever rules that person added on top of the
  # layout they started from — because that is what copying a `<style>` block out of a
  # page got you. The copy is yours to edit, which is what makes that acceptable.
  # The markup stays yours; only the rules come across.
  def copy_layout
    source = User.find_by!(username: params[:username]).profile

    if source.rendered.css.blank?
      return redirect_to profile_path(source.user), alert: "That page has no stylesheet to take."
    end

    layout = Layout.new(
      slug: "copied-from-#{source.user.username}",
      name: "@#{source.user.username}’s page",
      author: "@#{source.user.username}",
      description: "Taken from their page.",
      css: source.rendered.css
    )
    profile = current_user.profile
    # keep_own_rules: false — the copy is the point. If your own rules stayed on top,
    # taking a layout would do nothing visible on any page that had styled itself.
    profile.update!(document: LayoutApplication.new(profile, layout, keep_own_rules: false).document)

    redirect_to profile_path(current_user), notice: "Took @#{source.user.username}’s layout. It is yours to edit now."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to profile_path(params[:username]), alert: error.record.errors.full_messages.to_sentence
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
