# frozen_string_literal: true

# The signed-in owner's own details: the name, greeting, mood and headline that
# appear on their page beside their picture.
class AccountsController < ApplicationController
  before_action :require_authentication

  def update
    if current_user.update(account_params)
      redirect_to studio_path, notice: "Details saved."
    else
      redirect_to studio_path, alert: current_user.errors.full_messages.to_sentence
    end
  end

  private
    def account_params
      params.require(:user).permit(:name, :greeting, :mood, :headline)
    end
end
