# frozen_string_literal: true

# The editor: the page an owner writes in the browser, and the agent tokens that
# let a coding agent write the same page.
class StudioController < ApplicationController
  before_action :require_authentication

  def show
    @profile = current_user.profile
    @tokens = current_user.agent_tokens.recent_first
    @issued_token = flash[:agent_token]
    @conflicted = flash[:conflict]
  end

  def update
    profile = current_user.profile
    document = document_param
    expected = expected_version

    # The owner's agent can write the same page over the API while this editor is
    # open. A save built on the older revision is refused, and the copy the owner
    # typed is handed back rather than dropped.
    if expected && profile.version != expected
      @profile = profile.tap { |record| record.document = document }
      @tokens = current_user.agent_tokens.recent_first
      @conflicted = true
      return render :show, status: :conflict
    end

    if profile.update(document: document)
      redirect_to studio_path, notice: "Profile saved."
    else
      @profile = profile
      @tokens = current_user.agent_tokens.recent_first
      render :show, status: :unprocessable_content
    end
  end

  private
    def document_param
      attributes = params.require(:profile).permit(:document, :version)
      raise ActionController::ParameterMissing, :document unless attributes.key?(:document)

      attributes[:document].to_s
    end

    # The revision the editor was showing. An editor that sends none gets no
    # conflict check — it has no copy of the page to lose.
    def expected_version
      value = params.require(:profile).permit(:document, :version)[:version]
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
end
