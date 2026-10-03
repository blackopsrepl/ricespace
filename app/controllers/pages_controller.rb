# frozen_string_literal: true

# The parts of the site that are not a profile: the front page and the agent
# contract, which is also served as markdown so an agent can fetch it directly.
class PagesController < ApplicationController
  RECENT_PROFILES = 12

  def home
    @profiles = Profile.includes(:user).order(updated_at: :desc).limit(RECENT_PROFILES)
  end

  def agents
  end

  def agents_markdown
    render plain: AgentContract.markdown, content_type: "text/markdown; charset=utf-8"
  end
end
