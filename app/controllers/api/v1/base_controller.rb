# frozen_string_literal: true

module Api
  module V1
    # Everything under /api/v1 is called by a coding agent on behalf of the
    # account that issued its token, so there are no cookies and no CSRF: the
    # bearer token is the whole session.
    class BaseController < ActionController::API
      TOKEN_PATTERN = /\ABearer\s+(?<token>\S+)\z/

      # The account whose token made this request.
      attr_reader :current_user

      before_action :authenticate_agent!

      rescue_from ActionController::ParameterMissing do |error|
        fail_with(:bad_request, "missing_parameter", error.message)
      end

      rescue_from ActiveRecord::RecordInvalid do |error|
        fail_with(:unprocessable_content, "invalid_profile", "the profile was not accepted",
          details: error.record.errors.full_messages)
      end

      private
        def authenticate_agent!
          token = TOKEN_PATTERN.match(request.authorization)&.[](:token)
          agent_token = AgentToken.authenticate(token)

          return fail_with(:unauthorized, "invalid_token", "a valid agent token is required in the Authorization header") if agent_token.nil?

          @current_user = agent_token.user
        end

        def fail_with(status, code, message, details: nil)
          body = { error: { code: code, message: message } }
          body[:error][:details] = details if details
          render json: body, status: status
        end
    end
  end
end
