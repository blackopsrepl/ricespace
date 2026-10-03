# frozen_string_literal: true

# Agent tokens for the signed-in owner: issue one to hand to a coding agent,
# revoke one that should no longer work. The plaintext is flashed, never stored.
class AgentTokensController < ApplicationController
  before_action :require_authentication

  def create
    record = AgentToken.issue(user: current_user, name: token_params[:name])
    flash[:agent_token] = record.plaintext

    redirect_to studio_path, notice: "Agent token issued — copy it now, it is not shown again."
  end

  def destroy
    current_user.agent_tokens.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Agent token revoked."
  end

  private
    def token_params
      params.require(:agent_token).permit(:name)
    end
end
