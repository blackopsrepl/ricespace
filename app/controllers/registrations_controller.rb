# frozen_string_literal: true

# Signing up: pick a username, which becomes the profile URL, and a password.
# The account is signed in immediately; there is nothing to confirm.
#
# Rate limited by client: an open sign-up form is the price of the product, but an
# unbounded one is a machine for creating accounts as fast as a script can post.
class RegistrationsController < ApplicationController
  SIGN_UPS_PER_WINDOW = 5
  SIGN_UP_WINDOW = 3.minutes

  rate_limit to: SIGN_UPS_PER_WINDOW, within: SIGN_UP_WINDOW, only: :create,
    store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render_rate_limited }

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)

    if @user.save
      reset_session
      session[:user_id] = @user.id
      redirect_to studio_path, notice: "Welcome, #{@user.display_name}. Your profile page is yours to write."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def registration_params
      params.require(:user).permit(:username, :name, :email_address, :password)
    end

    def render_rate_limited
      redirect_to new_registration_path, alert: "Too many sign-ups from here. Try again in a few minutes."
    end
end
