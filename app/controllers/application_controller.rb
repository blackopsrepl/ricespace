# frozen_string_literal: true

# The site chrome: a dark shell around whatever a page shows, plus the flash
# region that carries an answer back to the person who caused it.
class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :signed_in?

  private
    # The account making this request, or nil for a visitor.
    def current_user
      @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
    end

    def signed_in?
      current_user.present?
    end

    def require_authentication
      return if signed_in?

      redirect_to new_session_path, alert: "Sign in to edit your profile."
    end
end
