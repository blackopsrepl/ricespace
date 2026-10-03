# frozen_string_literal: true

# The showcase: the rice.
#
# One per account, built from the owner's own studio — the screenshot, the facts about
# the machine, and the description of what is in it. This is where the "flex your rice"
# intent lives, so it gets the site's loudest treatment and the most of its logic.
class ShowcasesController < ApplicationController
  before_action :require_authentication

  def edit
    @showcase = current_user.showcase || current_user.build_showcase
    @shots = @showcase.shots
  end

  def update
    @showcase = current_user.showcase || current_user.build_showcase

    if @showcase.update(showcase_params)
      redirect_to studio_path, notice: "Showcase saved."
    else
      @shots = @showcase.shots
      flash.now[:alert] = @showcase.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  # A shot is added on its own, so a big screenshot does not have to be re-uploaded to
  # change a line of the description.
  def add_shot
    @showcase = current_user.showcase || current_user.build_showcase
    @showcase.save! if @showcase.new_record?

    shot = @showcase.shots.build(shot_params)
    shot.image.attach(params.require(:showcase_shot).require(:image))

    if shot.save
      redirect_to edit_showcase_path, notice: "Shot added."
    else
      redirect_to edit_showcase_path, alert: shot.errors.full_messages.to_sentence
    end
  rescue ActionController::ParameterMissing => error
    redirect_to edit_showcase_path, alert: error.message
  end

  def remove_shot
    shot = current_user.showcase.shots.find(params[:id])
    shot.destroy!

    redirect_to edit_showcase_path, notice: "Shot removed."
  end

  def move_shot
    shot = current_user.showcase.shots.find(params[:id])
    shot.move!(params[:direction])

    redirect_to edit_showcase_path, notice: "Reordered."
  end

  private
    def showcase_params
      params.require(:showcase).permit(:title, :summary, :details, *Showcase::FACTS.keys)
    end

    def shot_params
      params.require(:showcase_shot).permit(:caption)
    end
end
