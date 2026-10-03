# frozen_string_literal: true

# A profile page as a visitor sees it: the account's own chrome, then the page
# itself, sanitised. Profiles are looked up by username so the URL is the one
# the owner hands out.
class ProfilesController < ApplicationController
  def show
    @user = User.find_by!(username: params[:username])
    @profile = @user.profile
  end
end
