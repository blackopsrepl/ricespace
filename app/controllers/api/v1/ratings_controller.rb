# frozen_string_literal: true

module Api
  module V1
    # Ratings, over the API.
    #
    # The page endpoints cover what a page *says*; this covers what other people *said
    # about it*, which is the one fact on a page its owner does not write. A client that
    # can render a rice but not its score is rendering half the page — and an agent that
    # can push a folder but not express an opinion is not able to do the one thing on
    # this site that only another account can do.
    #
    # Two directions, and they are not the same operation:
    #
    # * read — the rating of the page the token speaks for, which is what an owner's
    #   own dashboard shows.
    # * write — this account's opinion of somebody else's page. Your own page is not
    #   yours to rate, here for the same reason it is not in the browser.
    class RatingsController < BaseController
      # GET /api/v1/ratings — the rating of the page this token speaks for.
      def show
        render json: { rating: presentation(current_user) }
      end

      # PUT /api/v1/ratings/:username — this account's opinion of that page.
      #
      # `like`, `dislike` or `none`. `none` withdraws an opinion rather than being a third
      # kind of one, which is what the button on the page does when you press it twice.
      def update
        page = User.find_by(username: params[:username].to_s.strip.downcase)
        return fail_with(:not_found, "unknown_page", "no page with that username") if page.nil?

        wanted = params.require(:rating).to_s
        return fail_with(:unprocessable_content, "unknown_rating", "rating must be like, dislike or none") unless
          %w[ like dislike none ].include?(wanted)

        return fail_with(:unprocessable_content, "own_page", "a page cannot rate itself") if page.id == current_user.id

        existing = current_user.given_ratings.find_by(user: page)

        if wanted == "none"
          existing&.destroy!
          return render json: { rating: presentation(page), yours: nil, changed: !existing.nil? }
        end

        score = wanted == "like" ? Rating::LIKE : Rating::DISLIKE

        # Setting the opinion you already have is not a change, and says so. It is
        # deliberately not a toggle here as it is in the browser: this is a `PUT`, and a
        # request that gets retried must not flip somebody's opinion. Withdrawing one is
        # the explicit `none`, so a client can always say what it means.
        if existing&.score == score
          return render json: { rating: presentation(page), yours: wanted, changed: false }
        end

        rating = existing || current_user.given_ratings.build(user: page)
        rating.score = score

        unless rating.save
          return fail_with(:unprocessable_content, "invalid_rating", "the rating was not accepted",
            details: rating.errors.full_messages)
        end

        render json: { rating: presentation(page), yours: wanted, changed: true }
      end

      private
        # A page's rating as the site counts it: one score plus the two counts it is made
        # of. `yours` is the token holder's own opinion of that page, which is what a
        # client needs to draw the button in the right state — and is separate from the
        # score, because the score is other people's.
        def presentation(page)
          {
            username: page.username,
            url: profile_url(page.username),
            score: page.score,
            likes: page.likes,
            dislikes: page.dislikes,
            raters: page.ratings.count,
            yours: current_user.rating_value_for(page)
          }
        end
    end
  end
end
