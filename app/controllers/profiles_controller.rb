# frozen_string_literal: true

# A profile page as a visitor sees it: the site's own chrome, then the page itself
# — markup and the author's stylesheet, cleaned on render. Profiles are looked up
# by username so the URL is the one the owner hands out.
class ProfilesController < ApplicationController
  def show
    @user = User.find_by!(username: params[:username])
    @profile = @user.profile
    @rendered = @profile.rendered
  end
end
