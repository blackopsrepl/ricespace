# frozen_string_literal: true

module Api
  module V1
    # The profile of the account that owns the presented token.
    #
    # An agent reads the document here, rewrites it, and writes it back. The
    # response carries both the document (what the author wrote, exactly as
    # stored) and the rendered markup (what a visitor will see), so an agent can
    # tell whether its HTML survived the sanitiser without a browser. It also
    # carries the revision it just read, which the agent sends back on its next
    # write.
    class ProfilesController < BaseController
      def show
        render json: { profile: presentation(current_user.profile) }
      end

      def update
        profile = current_user.profile
        expected = expected_version

        # Refuse rather than overwrite: an agent that edited a stale copy of the
        # page has to re-read and reapply, because it cannot see what it is about
        # to lose.
        return reject_stale(profile) unless profile.version == expected

        profile.update!(document: document_param)

        render json: { profile: presentation(profile) }
      end

      private
        # An empty document is a page with nothing on it, which an agent may
        # legitimately want. A *missing* document is a request that forgot to say
        # what to write, and must not be read as "erase the page".
        def document_param
          attributes = profile_params
          raise ActionController::ParameterMissing, :document unless attributes.key?(:document)

          attributes[:document].to_s
        end

        # The revision the agent edited. An agent that has read the profile always
        # has this; a write without it is a blind write and is refused.
        def expected_version
          value = profile_params[:version]
          raise ActionController::ParameterMissing, :version if value.blank?

          Integer(value)
        rescue ArgumentError, TypeError
          raise ActionController::ParameterMissing, :version
        end

        def profile_params
          params.require(:profile).permit(:document, :version)
        end

        def reject_stale(profile)
          fail_with(:conflict, "stale_document",
            "the profile moved since you read it; re-read it and reapply your edit",
            details: { current_version: profile.version })
        end

        def presentation(profile)
          {
            username: current_user.username,
            url: profile_url(current_user.username),
            document: profile.document,
            rendered: profile.markup.to_s,
            version: profile.version,
            updated_at: profile.updated_at.iso8601,
            limits: { document_bytes: Profile::MAX_DOCUMENT_LENGTH, rendered_bytes: ProfileMarkup::MAX_BYTES }
          }
        end
    end
  end
end
