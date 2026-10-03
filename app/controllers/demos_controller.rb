# frozen_string_literal: true

# The demos on a page: list one, take it off. The facts of the release are the entry —
# a demo is not only a video, and most of them link to a catalogue rather than a player.
class DemosController < ApplicationController
  before_action :require_authentication

  def create
    demo = current_user.demos.build(demo_params)

    if demo.save
      redirect_to studio_path, notice: "Demo added to your page."
    else
      redirect_to studio_path, alert: demo.errors.full_messages.to_sentence
    end
  end

  def update
    demo = current_user.demos.find(params[:id])

    if demo.update(demo_params)
      redirect_to studio_path, notice: "Demo updated."
    else
      redirect_to studio_path, alert: demo.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.demos.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Demo removed."
  end

  private
    def demo_params
      params.require(:demo).permit(:title, :group_name, :party, :release_year, :platform,
        :category, :ranking, :url, :watch_note)
    end
end
