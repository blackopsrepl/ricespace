# frozen_string_literal: true

class Favorite < ApplicationRecord
  belongs_to :user
  belongs_to :favorited_user, class_name: "User"

  validates :user_id, uniqueness: { scope: :favorited_user_id }
  validate :cannot_favorite_self

  private
    def cannot_favorite_self
      errors.add(:favorited_user, "cannot be yourself") if user_id == favorited_user_id
    end
end
