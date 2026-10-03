# frozen_string_literal: true

# The signed-in owner's own account: the details shown beside their picture, and
# closing the account.
#
# Deleting is a button on the studio after a deliberate confirmation rather than a
# link in a menu. It is the owner's own account or nothing: there is no path here
# to delete somebody else's, and the site's own account cannot be closed because
# every page on the site lists it.
class AccountsController < ApplicationController
  before_action :require_authentication

  def update
    if current_user.update(account_params)
      redirect_to studio_path, notice: "Details saved."
    else
      redirect_to studio_path, alert: current_user.errors.full_messages.to_sentence
    end
  end

  def destroy
    if current_user.admin?
      return redirect_to studio_path, alert: "The site's own account cannot be closed."
    end

    username = current_user.username
    current_user.close!
    reset_session

    redirect_to root_path, notice: "The page @#{username} is gone, with everything on it."
  end

  private
    def account_params
      params.require(:user).permit(:name, :greeting, :mood, :headline)
    end
end
