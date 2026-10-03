# frozen_string_literal: true

require "test_helper"

# Rating a page, and what a score is allowed to mean.
#
# The number on a page is a count of people, not of clicks: one opinion per account per
# page, changing your mind edits that opinion, and nobody rates their own page. Get any of
# those wrong and the ranking stops being what it claims to be — which matters more here
# than elsewhere, because the ranking is the one thing on the site that other people,
# rather than the page's owner, decide.
class RatingTest < ActiveSupport::TestCase
  setup do
    @page = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @visitor = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @other = User.create!(username: "ronald", email_address: "r@example.com", password: "correct horse battery")
  end

  test "a visitor likes a page and the page's score goes up by one" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)

    assert_equal 1, @page.score
    assert_equal 1, @page.likes
    assert_equal 0, @page.dislikes
  end

  test "a dislike moves the score the other way" do
    @page.ratings.create!(author: @visitor, score: Rating::DISLIKE)

    assert_equal(-1, @page.score)
    assert_equal 1, @page.dislikes
  end

  test "one account rates a page once" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)

    second = @page.ratings.build(author: @visitor, score: Rating::LIKE)

    refute_predicate second, :valid?
    assert_equal 1, @page.reload.score, "a second opinion from the same person is not a second point"
  end

  test "changing your mind moves the score without counting you twice" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)

    rating = @page.ratings.find_by(author: @visitor)
    rating.update!(score: Rating::DISLIKE)

    assert_equal(-1, @page.reload.score)
    assert_equal 1, @page.ratings.count
  end

  test "a page's owner cannot rate their own page" do
    rating = @page.ratings.build(author: @page, score: Rating::LIKE)

    refute_predicate rating, :valid?
    assert_match(/own page/, rating.errors.full_messages.to_sentence)
    assert_equal 0, @page.reload.score
  end

  test "two people are worth two points" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)
    @page.ratings.create!(author: @other, score: Rating::LIKE)

    assert_equal 2, @page.score
  end

  test "an account's own ratings go with it when it closes" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)
    assert_equal 1, @page.score

    @visitor.destroy!

    assert_equal 0, @page.reload.score, "a closed account leaves no vote behind"
  end

  test "what a visitor said about a page can be looked up for the page to show" do
    @page.ratings.create!(author: @visitor, score: Rating::DISLIKE)

    assert_equal Rating::DISLIKE, @visitor.rating_for(@page)
    assert_nil @other.rating_for(@page)
  end
end
