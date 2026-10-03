# frozen_string_literal: true

# Liking or disliking somebody's page.
#
# Signed in only, and one per person per page: an opinion you can leave repeatedly is not
# an opinion, it is a counter, and a counter with an author is what makes it answerable.
#
# Pressing the thing you already pressed takes your opinion back, the way a toggle on the
# era's pages worked — without that there is no way to un-rate a page, and a page you
# rated once in error is rated forever.
class RatingsController < ApplicationController
  before_action :require_authentication

  def create
    page = User.find_by!(username: params[:username])
    score = params[:score].to_i

    unless Rating::SCORES.include?(score)
      return redirect_to profile_path(page), alert: "That is not a rating."
    end

    existing = current_user.given_ratings.find_by(user: page)

    if existing && existing.score == score
      existing.destroy!
      return redirect_to profile_path(page), notice: unrated_notice(page)
    end

    rating = existing || current_user.given_ratings.build(user: page)
    rating.score = score

    if rating.save
      redirect_to profile_path(page), notice: rated_notice(page, score)
    else
      redirect_to profile_path(page), alert: rating.errors.full_messages.to_sentence
    end
  end

  private
    def rated_notice(page, score)
      verb = score == Rating::LIKE ? "Liked" : "Disliked"
      "#{verb} @#{page.username}’s page — it is on #{page.score} now."
    end

    def unrated_notice(page)
      "Took your rating off @#{page.username}’s page — it is on #{page.score} now."
    end
end
