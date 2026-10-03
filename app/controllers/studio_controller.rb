# frozen_string_literal: true

# The editor: the page an owner writes in the browser, the page's song, and the
# agent tokens that let a coding agent write the same page.
#
# The song is edited through this controller rather than one of its own because it
# is part of the page, and therefore takes the page's revision check: a song saved
# from a stale editor is a song saved over somebody else's work.
class StudioController < ApplicationController
  before_action :require_authentication

  def show
    @profile = current_user.profile
    @tokens = current_user.agent_tokens.recent_first
    @issued_token = flash[:agent_token]
    @conflicted = flash[:conflict]
    load_page_bits
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
      load_page_bits
      @conflicted = true
      return render :show, status: :conflict
    end

    if profile.update(document: document)
      redirect_to studio_path, notice: "Profile saved."
    else
      @profile = profile
      load_page_bits
      render :show, status: :unprocessable_content
    end
  end

  # The song, saved through the page it belongs to.
  def update_song
    profile = current_user.profile
    expected = expected_version

    if expected && profile.version != expected
      @profile = profile
      load_page_bits
      @conflicted = true
      return render :show, status: :conflict
    end

    if profile.update(song_params)
      redirect_to studio_path, notice: profile.song? ? "Song saved." : "Song removed."
    else
      @profile = profile
      load_page_bits
      flash.now[:alert] = profile.errors.full_messages.to_sentence
      render :show, status: :unprocessable_content
    end
  end

  private
    def load_page_bits
      @tokens ||= current_user.agent_tokens.recent_first
      @picture = current_user.profile_picture
      @blurbs = current_user.blurbs.in_order
      @friendships = current_user.friendships.in_order.includes(:friend)
      @friends = @friendships.map(&:friend)
    end

    def document_param
      attributes = params.require(:profile).permit(:document, :version)
      raise ActionController::ParameterMissing, :document unless attributes.key?(:document)

      attributes[:document].to_s
    end

    def song_params
      params.require(:profile).permit(:song_url, :song_title)
    end

    # The revision the editor was showing. An editor that sends none gets no
    # conflict check — it has no copy of the page to lose.
    def expected_version
      value = params.require(:profile).permit(:document, :song_url, :song_title, :version)[:version]
      return nil if value.blank?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
end
