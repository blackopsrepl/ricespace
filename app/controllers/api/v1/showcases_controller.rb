# frozen_string_literal: true

module Api
  module V1
    # The showcase — the rice — for the account that owns the presented token.
    #
    # Same reasoning as the profile endpoint: this is the owner's own second editing
    # tool, so it reads and writes the same record the studio does. The response names
    # each fact under its own key *and* as a list of filled-in pairs, because the list is
    # what a terminal renders and the keys are what a script sets.
    class ShowcasesController < BaseController
      def show
        render json: { showcase: presentation(showcase) }
      end

      def update
        showcase.assign_attributes(showcase_params)

        unless showcase.save
          return fail_with(:unprocessable_content, "invalid_showcase",
            "the showcase was not accepted", details: showcase.errors.full_messages)
        end

        render json: { showcase: presentation(showcase) }
      end

      private
        # An account that has never built a showcase gets an empty one rather than a 404:
        # "you have no showcase" is not an error, and a client should not have to special
        # case the first run.
        def showcase
          @showcase ||= current_user.showcase || current_user.build_showcase
        end

        def showcase_params
          params.require(:showcase).permit(:title, :summary, :details, *Showcase::FACTS.keys)
        end

        def presentation(record)
          {
            username: current_user.username,
            url: profile_url(current_user.username, anchor: "showcase"),
            title: record.title,
            summary: record.summary,
            details: record.details,
            facts: Showcase::FACTS.keys.index_with { |fact| record.public_send(fact) },
            filled: record.facts.map { |label, value| { label: label, value: value } },
            shots: record.shots.map do |shot|
              {
                id: shot.id,
                caption: shot.caption,
                position: shot.position,
                bytes: shot.image.attached? ? shot.image.blob.byte_size : nil,
                url: shot.image.attached? ? rails_blob_url(shot.image.blob) : nil
              }
            end,
            updated_at: record.updated_at&.iso8601,
            limits: {
              title_bytes: Showcase::MAX_LINE_LENGTH,
              summary_bytes: 200,
              details_bytes: Showcase::MAX_DETAILS_LENGTH
            }
          }
        end
    end
  end
end
