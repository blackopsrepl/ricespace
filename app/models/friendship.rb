# frozen_string_literal: true

# A friend: one account on another account's friends list.
#
# The list is the account's own — there is no request/accept dance, because what
# this imitates never had one, and a friend you cannot add is not the feature. The
# friendship is stored once, on the account whose page shows it, and `friend` is
# whoever was added.
#
# The order is the owner's, and it is the whole point of the list: the first eight
# are the ones the page shows first.
class Friendship < ApplicationRecord
  belongs_to :user
  belongs_to :friend, class_name: "User"

  validates :friend_id, uniqueness: { scope: :user_id }
  validate :not_self

  scope :in_order, -> { order(:position, :id) }

  before_create :append_to_end

  # Move this friend one place earlier or later. Positions are rewritten as a dense
  # sequence, so the order shown is the order the owner set.
  def move!(direction)
    siblings = user.friendships.in_order.to_a
    index = siblings.index(self)
    return if index.nil?

    target = direction.to_s == "up" ? index - 1 : index + 1
    return if target.negative? || target >= siblings.size

    siblings[index], siblings[target] = siblings[target], siblings[index]
    siblings.each_with_index { |friendship, position| friendship.update_column(:position, position) }
  end

  private
    def not_self
      errors.add(:friend, "cannot be yourself") if friend_id.present? && friend_id == user_id
    end

    def append_to_end
      self.position = (user&.friendships&.maximum(:position) || -1) + 1
    end
end
