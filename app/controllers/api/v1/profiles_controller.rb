# frozen_string_literal: true

module Api
  module V1
    # The profile of the account that owns the presented token.
    #
    # An agent is a second editing tool for the page its owner already has in the
    # browser — not a separate channel — so this is the same read/whole-document
    # write the studio does, and the same revision check.
    #
    # The response carries the document as stored, the markup and stylesheet as a
    # visitor will get them, and the revision that was just read, which the agent
    # sends back on its next write. The separated stylesheet is the point: a
    # profile's layout lives in `<style>`, and an agent that never sees which of
    # its rules survived is editing blind.
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
        PeerWrite.publish_local(current_user)

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
          rendered = profile.rendered

          {
            username: current_user.username,
            url: profile_url(current_user.username),
            document: profile.document,
            html: rendered.html.to_s,
            css: rendered.css,
            version: profile.version,
            updated_at: profile.updated_at.iso8601,
            limits: {
              document_bytes: Profile::MAX_DOCUMENT_LENGTH,
              html_bytes: ProfileMarkup::MAX_BYTES,
              css_bytes: PageCss::MAX_BYTES
            }
          }
        end
    end
  end
end
