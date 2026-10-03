# frozen_string_literal: true

require "test_helper"

class ShowcaseShotTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @showcase = @user.create_showcase
  end

  test "shots are appended in the order they were added" do
    first = @showcase.shots.create!
    second = @showcase.shots.create!

    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "a shot is refused if the file is not an image" do
    shot = @showcase.shots.build
    shot.image.attach(io: StringIO.new("not an image"), filename: "payload.txt", content_type: "text/plain")

    refute_predicate shot, :valid?
    assert_match "must be an image", shot.errors[:image].to_s
  end

  test "a shot over the size limit is refused" do
    shot = @showcase.shots.build
    shot.image.attach(io: StringIO.new("0" * (ShowcaseShot::MAX_BYTES + 1)), filename: "big.png",
      content_type: "image/png")

    refute_predicate shot, :valid?
    assert_match "smaller than", shot.errors[:image].to_s
  end

  test "moving a shot up swaps it with the one before it" do
    first = @showcase.shots.create!
    second = @showcase.shots.create!
    third = @showcase.shots.create!

    third.move!("up")

    assert_equal [ first, third, second ], @showcase.shots.reload.to_a
    assert_equal [ 0, 1, 2 ], @showcase.shots.map(&:position)
  end

  test "moving the first shot up, or the last down, does nothing" do
    first = @showcase.shots.create!
    last = @showcase.shots.create!

    first.move!("up")
    last.move!("down")

    assert_equal [ first, last ], @showcase.shots.reload.to_a
  end

  test "deleting the showcase takes its shots" do
    @showcase.shots.create!

    assert_difference -> { ShowcaseShot.count } => -1 do
      @showcase.destroy
    end
  end
end
