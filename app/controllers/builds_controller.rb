# frozen_string_literal: true

# The hardware on a page: add a build, photograph it, edit it, take it off. Nothing is
# uploaded by itself — each photo is its own upload, so a big one does not have to be sent
# again to change a line of the description.
class BuildsController < ApplicationController
  before_action :require_authentication

  def create
    build = current_user.builds.build(build_params)

    if build.save
      if params.dig(:build, :photo).present?
        photo = build.photos.build(caption: params.dig(:build, :photo_caption))
        photo.image.attach(params[:build][:photo])

        unless photo.save
          return redirect_to studio_path,
            alert: "Build saved, but the photo was not: #{photo.errors.full_messages.to_sentence}"
        end
      end

      redirect_to studio_path, notice: "Build added to your page."
    else
      redirect_to studio_path, alert: build.errors.full_messages.to_sentence
    end
  end

  def update
    build = current_user.builds.find(params[:id])

    if build.update(build_params)
      redirect_to studio_path, notice: "Build updated."
    else
      redirect_to studio_path, alert: build.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.builds.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Build removed."
  end

  # A photo is added on its own, so the description can be edited without re-sending it.
  def add_photo
    build = current_user.builds.find(params[:id])
    photo = build.photos.build(caption: params[:caption])
    photo.image.attach(params.require(:photo))

    if photo.save
      redirect_to studio_path, notice: "Photo added."
    else
      redirect_to studio_path, alert: photo.errors.full_messages.to_sentence
    end
  rescue ActionController::ParameterMissing => error
    redirect_to studio_path, alert: error.message
  end

  def remove_photo
    photo = current_user.builds.find(params[:id]).photos.find(params[:photo_id])
    photo.destroy!

    redirect_to studio_path, notice: "Photo removed."
  end

  private
    def build_params
      params.require(:build).permit(:title, :kind, :summary, :details, :specs, :cooling)
    end
end
