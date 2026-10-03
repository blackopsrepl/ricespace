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
    # The videos and streams, which are links to somebody else's service.
    @stream_links = @user.stream_links.order(:created_at)
    # The demoscene demos, which are their own category: the release facts are the entry.
    @demos = @user.demos.in_order
    # The hardware, which is a physical thing photographed rather than a desktop.
    @builds = @user.builds.in_order
    @can_edit = signed_in? && current_user == @user

    # Track views and last seen — the MySpace "viewed X times" and online status.
    # A visit is somebody looking at the page, so the owner's own views do not
    # count and only the owner's own visits move their last-seen — "online now"
    # means the owner is actually here, not that somebody looked at them.
    @profile.increment!(:view_count) unless @can_edit
    @user.touch(:last_seen_at) if @can_edit

    # What people think of this page, and what this visitor said. One grouped read for
    # the counts rather than three sums.
    @likes = @user.likes
    @dislikes = @user.dislikes

    # Whether this account has blocked that one. The only state the page needs about the
    # relationship between two accounts; a favourite had no number and no effect, so it is
    # gone rather than kept as a second way to say "I like this".
    @blocked = signed_in? && current_user != @user ? current_user.blocked_users.include?(@user) : false
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

  # Block a user — they can't see your page or comment on it.
  def block
    target = User.find_by!(username: params[:username])
    current_user.blocks.find_or_create_by!(blocked_user: target)
    redirect_to profile_path(target), notice: "Blocked @#{target.username}."
  rescue ActiveRecord::RecordInvalid => error
    redirect_to profile_path(params[:username]), alert: error.record.errors.full_messages.to_sentence
  end

  def unblock
    target = User.find_by!(username: params[:username])
    current_user.blocks.find_by(blocked_user: target)&.destroy
    redirect_to profile_path(target), notice: "Unblocked @#{target.username}."
  end
end
