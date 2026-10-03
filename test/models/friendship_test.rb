# frozen_string_literal: true

require "test_helper"

class FriendshipTest < ActiveSupport::TestCase
  setup do
    @user = create_user("vittorio")
  end

  test "adding a friend puts them at the end of the list" do
    first = create_user("cordelia")
    second = create_user("wes")

    @user.friendships.create!(friend: first)
    @user.friendships.create!(friend: second)

    assert_equal [ first, second ], @user.friendships.in_order.map(&:friend)
  end

  test "the list can be reordered, and the order sticks" do
    first = create_user("cordelia")
    second = create_user("wes")
    @user.friendships.create!(friend: first)
    @user.friendships.create!(friend: second)

    @user.friendships.in_order.last.move!("up")

    assert_equal [ second, first ], @user.friendships.in_order.reload.map(&:friend)

    # And moving past an end does nothing rather than corrupting the order.
    @user.friendships.in_order.first.move!("up")
    assert_equal [ second, first ], @user.friendships.in_order.reload.map(&:friend)

    @user.friendships.in_order.last.move!("down")
    assert_equal [ second, first ], @user.friendships.in_order.reload.map(&:friend)
  end

  test "somebody is on a list once" do
    friend = create_user("cordelia")
    @user.friendships.create!(friend: friend)

    assert_not @user.friendships.new(friend: friend).valid?
  end

  test "an account cannot add itself" do
    assert_not @user.friendships.new(friend: @user).valid?
  end

  test "deleting an account takes it off other people's lists" do
    friend = create_user("cordelia")
    @user.friendships.create!(friend: friend)

    assert_difference -> { Friendship.count } => -1 do
      friend.destroy
    end
  end

  private
    def create_user(username)
      User.create!(username: username, email_address: "#{username}@example.com", password: "correct horse battery")
    end
end
