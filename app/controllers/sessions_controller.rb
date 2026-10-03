# frozen_string_literal: true

# Log in and log out. A session is a cookie holding the account id; the agent
# API does not use sessions at all.
#
# Rate limited by client so a list of addresses and one password can be tried at
# human speed at worst. Per client, not per account: locking an account after
# failed attempts would let anyone lock anybody out.
class SessionsController < ApplicationController
  ATTEMPTS_PER_WINDOW = 10
  ATTEMPT_WINDOW = 3.minutes

  rate_limit to: ATTEMPTS_PER_WINDOW, within: ATTEMPT_WINDOW, only: :create,
    store: RATE_LIMIT_STORE, by: -> { request.remote_ip },
    with: -> { render_rate_limited }

  def new
  end

  def create
    user = User.find_by(email_address: params[:email_address].to_s.strip.downcase)

    if user&.authenticate(params[:password].to_s)
      reset_session
      session[:user_id] = user.id
      redirect_to studio_path, notice: "Signed in as #{user.display_name}."
    else
      @email_address = params[:email_address]
      flash.now[:alert] = "That email address and password do not match an account."
      render :new, status: :unauthorized
    end
  end

  def destroy
    reset_session
    redirect_to root_path, notice: "Signed out."
  end

  private
    # The form again with the answer, rather than a bare 429 body: the person who
    # hits this is far more likely to be typing than to be a script.
    def render_rate_limited
      @email_address = params[:email_address]
      flash.now[:alert] = "Too many sign-in attempts. Try again in a few minutes."

      render :new, status: :too_many_requests
    end
end
