# frozen_string_literal: true

# Reacting to somebody's post.
#
# Signed in only, and one per person per post: an opinion you can leave repeatedly is not an
# opinion, it is a counter, and a counter with an author is what makes it answerable.
#
# Pressing the thing you already pressed takes your opinion back, the way a toggle on the
# era's pages worked — without that there is no way to un-react, and a post you reacted to
# once in error is reacted to forever.
#
# A post is anything that was posted: the page itself, the rice, a shot of it, a build, a
# demo, a link. The target arrives as a kind and an id, so the same action serves all of them
# and the page keeps one reaction control rather than one per feature.
class RatingsController < ApplicationController
  before_action :require_authentication

  # The kinds a reaction may be left on, by the name the page sends.
  TARGETS = {
    "page" => "User",
    "showcase" => "Showcase",
    "shot" => "ShowcaseShot",
    "build" => "Build",
    "photo" => "BuildPhoto",
    "demo" => "Demo",
    "link" => "StreamLink",
    "blurb" => "Blurb"
  }.freeze

  def create
    page = User.find_by!(username: params[:username])
    thing = target(page)

    return redirect_to profile_path(page), alert: "There is no such post." if thing.nil?

    score = params[:score].to_i
    return redirect_to profile_path(page), alert: "That is not a reaction." unless Rating::SCORES.include?(score)

    existing = current_user.given_ratings.find_by(rateable: thing)

    if existing && existing.score == score
      existing.destroy!
      return redirect_to back_to(page), notice: unreacted_notice(page)
    end

    rating = existing || current_user.given_ratings.build(rateable: thing)
    rating.score = score

    if rating.save
      redirect_to back_to(page), notice: reacted_notice(page, score)
    else
      redirect_to back_to(page), alert: rating.errors.full_messages.to_sentence
    end
  end

  private
    # What was reacted to. No kind given means the page itself, which is what every existing
    # link on a page sends — so nothing that was already wired had to change.
    def target(page)
      kind = params[:kind].presence
      return page if kind.nil?

      klass = TARGETS[kind]
      return nil if klass.nil?

      thing = klass.constantize.find_by(id: params[:id])
      return nil if thing.nil?

      # Somebody else's post only. The page in the path is the page whose wall it is.
      owner = thing.respond_to?(:owner) ? thing.owner : nil
      return nil unless owner&.id == page.id

      thing
    end

    # Back where the control was pressed, so reacting to the rice leaves you looking at the
    # rice rather than at the top of the page.
    def back_to(page)
      anchor = params[:anchor].presence
      profile_path(page, anchor: anchor)
    end

    # A reaction says what it was about, because "liked" on its own does not tell you whether
    # it was the page or the rice on it.
    def reacted_notice(page, score)
      verb = score == Rating::LIKE ? "Liked" : "Disliked"
      "#{verb} #{about(page)} — @#{page.username} is on #{page.score} now."
    end

    def unreacted_notice(page)
      "Took your reaction off #{about(page)} — @#{page.username} is on #{page.score} now."
    end

    def about(page)
      kind = params[:kind].presence
      return "@#{page.username}’s page" if kind.nil? || kind == "page"

      label = kind.humanize.downcase
      anchor = params[:anchor].presence
      anchor ? "the #{label} (#{anchor})" : "the #{label}"
    end
end
