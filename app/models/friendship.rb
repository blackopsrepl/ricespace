# frozen_string_literal: true

# A friend: one account on another account's friends list.
#
# The list is the account's own — there is no request/accept dance, because what
# this imitates never had one, and a friend you cannot add is not the feature. The
# friendship is stored once, on the account whose page shows it, and `friend` is
# whoever was added.
class Friendship < ApplicationRecord
  belongs_to :user
  belongs_to :friend, class_name: "User"

  validates :friend_id, uniqueness: { scope: :user_id }
  validate :not_self

  scope :recent_first, -> { order(created_at: :desc) }

  private
    def not_self
      errors.add(:friend, "cannot be yourself") if friend_id.present? && friend_id == user_id
    end
end
