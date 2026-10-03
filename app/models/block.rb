# frozen_string_literal: true

class Block < ApplicationRecord
  belongs_to :user
  belongs_to :blocked_user, class_name: "User"

  validates :user_id, uniqueness: { scope: :blocked_user_id }
  validate :cannot_block_self

  private
    def cannot_block_self
      errors.add(:blocked_user, "cannot be yourself") if user_id == blocked_user_id
    end
end
