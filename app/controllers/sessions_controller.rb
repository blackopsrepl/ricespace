# frozen_string_literal: true

# Log in and log out. A session is a cookie holding the account id; the agent
# API does not use sessions at all.
class SessionsController < ApplicationController
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
end
