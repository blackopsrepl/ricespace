# frozen_string_literal: true

module Api
  module V1
    # Reactions, over the API.
    #
    # The page endpoints cover what a page *says*; this covers what other people *said about
    # it*, which is the one fact on a page its owner does not write. A client that can render
    # a rice but not its score is rendering half the page — and an agent that can push a
    # folder but not express an opinion is not able to do the one thing on this site that
    # only another account can do.
    #
    # Two directions, and they are not the same operation:
    #
    # * read — the reactions on the page the token speaks for, which is what an owner's own
    #   dashboard shows. The page's score is the page plus everything posted on it.
    # * write — this account's opinion of somebody else's post. Your own post is not yours to
    #   react to, here for the same reason it is not in the browser.
    #
    # A reaction can be left on anything that was posted, not only on a page, because that is
    # what people actually react to. A target is named by kind and id, and a page is one of
    # the kinds — so an existing client that only knows about pages keeps working.
    class RatingsController < BaseController
      # The kinds a reaction may be left on, by the name a client sends.
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

      # GET /api/v1/ratings — the reactions on the page this token speaks for.
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

        react_to(page, page)
      end

      # PUT /api/v1/ratings/:username/:kind/:id — this account's opinion of one posted thing.
      #
      # The same act as reacting to the page, aimed at something specific: the rice, a shot
      # of it, a build, a demo, a link. That is what a person is looking at when they decide
      # they like it, and a page-only reaction forces them to say it about the page instead.
      def update_target
        page = User.find_by(username: params[:username].to_s.strip.downcase)
        return fail_with(:not_found, "unknown_page", "no page with that username") if page.nil?

        klass = TARGETS[params[:kind].to_s]
        return fail_with(:unprocessable_content, "unknown_kind", "kind must be one of #{TARGETS.keys.join(", ")}") if klass.nil?

        thing = klass.constantize.find_by(id: params[:id])
        return fail_with(:not_found, "unknown_post", "no #{params[:kind]} with that id") if thing.nil?

        # Somebody else's post only. A reaction on a post that is not on this page is a
        # reaction on a page the token does not speak for, which is a different request.
        owner = thing.respond_to?(:owner) ? thing.owner : nil
        return fail_with(:not_found, "unknown_post", "no #{params[:kind]} with that id") unless owner&.id == page.id

        react_to(thing, page)
      end

      private
        def react_to(thing, page)
          wanted = params.require(:rating).to_s
          return fail_with(:unprocessable_content, "unknown_rating", "rating must be like, dislike or none") unless
            %w[ like dislike none ].include?(wanted)

          owner = thing.respond_to?(:owner) ? thing.owner : nil
          if owner&.id == current_user.id
            return fail_with(:unprocessable_content, "own_post", "you cannot react to your own post")
          end

          existing = current_user.given_ratings.find_by(rateable: thing)

          if wanted == "none"
            existing&.destroy!
            return render json: { rating: presentation(page), yours: nil, changed: !existing.nil? }
          end

          score = wanted == "like" ? Rating::LIKE : Rating::DISLIKE

          # Setting the opinion you already have is not a change, and says so. Deliberately
          # not a toggle here as it is in the browser: this is a `PUT`, and a request that
          # gets retried must not flip somebody's opinion. Withdrawing one is the explicit
          # `none`, so a client can always say what it means.
          if existing&.score == score
            return render json: { rating: presentation(page), yours: wanted, changed: false }
          end

          rating = existing || current_user.given_ratings.build(rateable: thing)
          rating.score = score

          unless rating.save
            return fail_with(:unprocessable_content, "invalid_rating", "the rating was not accepted",
              details: rating.errors.full_messages)
          end

          render json: { rating: presentation(page), yours: wanted, changed: true }
        end

        # A page's reactions as the site counts them: one score plus the two counts it is made
        # of, over the page and everything posted on it. `yours` is the token holder's own
        # opinion of the page itself — separate from the score, because the score is other
        # people's.
        def presentation(page)
          {
            username: page.username,
            url: profile_url(page.username),
            score: page.score,
            likes: page.likes,
            dislikes: page.dislikes,
            raters: page.reaction_scope.distinct.count(:author_id),
            yours: current_user.rating_value_for(page)
          }
        end
    end
  end
end
