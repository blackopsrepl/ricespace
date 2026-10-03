# frozen_string_literal: true

# The friends list, which is the account's own: add somebody by username, take
# them off again.
class FriendshipsController < ApplicationController
  before_action :require_authentication

  def create
    friend = User.find_by(username: params[:username].to_s.strip.downcase)

    if friend.nil?
      return redirect_to studio_path, alert: "No page with the username #{params[:username].inspect}."
    end

    friendship = current_user.friendships.find_or_initialize_by(friend: friend)

    if friendship.save
      redirect_to studio_path, notice: "#{friend.display_name} is on your friends list."
    else
      redirect_to studio_path, alert: friendship.errors.full_messages.to_sentence
    end
  end

  def destroy
    current_user.friendships.find(params[:id]).destroy!

    redirect_to studio_path, notice: "Removed from your friends list."
  end

  # Reorder the list. The first few are the ones a page shows first, so the order
  # is what makes the list the owner's rather than alphabetical.
  def move
    friendship = current_user.friendships.find(params[:id])
    friendship.move!(params[:direction])

    redirect_to studio_path, notice: "Reordered."
  end
end
