# frozen_string_literal: true

# Signing up: pick a username, which becomes the profile URL, and a password.
# The account is signed in immediately; there is nothing to confirm.
class RegistrationsController < ApplicationController
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
end
