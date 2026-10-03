# frozen_string_literal: true

# The blocks of text a page is written out of. An owner manages their own.
class BlurbsController < ApplicationController
  before_action :require_authentication

  def create
    blurb = current_user.blurbs.build(blurb_params)

    if blurb.save
      redirect_to studio_path, notice: "Added “#{blurb.title}”."
    else
      redirect_to studio_path, alert: blurb.errors.full_messages.to_sentence
    end
  end

  def update
    blurb = current_user.blurbs.find(params[:id])

    if blurb.update(blurb_params)
      redirect_to studio_path, notice: "Saved “#{blurb.title}”."
    else
      redirect_to studio_path, alert: blurb.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.blurbs.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Blurb removed."
  end

  def move
    blurb = current_user.blurbs.find(params[:id])
    blurb.move!(params[:direction])

    redirect_to studio_path, notice: "Reordered."
  end

  private
    def blurb_params
      params.require(:blurb).permit(:title, :body)
    end
end
