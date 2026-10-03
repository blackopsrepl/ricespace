# frozen_string_literal: true

require "test_helper"

# Reacting to something posted, and what a score is allowed to mean.
#
# The number on a page is a count of people, not of clicks: one opinion per account per
# thing, changing your mind edits that opinion, and nobody reacts to their own post. Get any
# of those wrong and the ranking stops being what it claims to be — which matters more here
# than elsewhere, because the ranking is the one thing on the site that other people, rather
# than the page's owner, decide.
#
# The second half is the part that is new: a page's score is the page *and everything posted
# on it*, so reacting to somebody's rice lifts their page. A page is what is on it.
class RatingTest < ActiveSupport::TestCase
  setup do
    @page = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @visitor = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @other = User.create!(username: "ronald", email_address: "r@example.com", password: "correct horse battery")
  end

  test "a visitor likes a page and the page's score goes up by one" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)

    assert_equal 1, @page.score
    assert_equal 1, @page.likes
    assert_equal 0, @page.dislikes
  end

  test "a dislike moves the score the other way" do
    @page.reactions.create!(author: @visitor, score: Rating::DISLIKE)

    assert_equal(-1, @page.score)
    assert_equal 1, @page.dislikes
  end

  test "one account reacts to a page once" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)

    second = @page.reactions.build(author: @visitor, score: Rating::LIKE)

    refute_predicate second, :valid?
    assert_equal 1, @page.reload.score, "a second opinion from the same person is not a second point"
  end

  test "changing your mind moves the score without counting you twice" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)

    rating = @page.reactions.find_by(author: @visitor)
    rating.update!(score: Rating::DISLIKE)

    assert_equal(-1, @page.reload.score)
    assert_equal 1, @page.reactions.count
  end

  test "a page's owner cannot react to their own page" do
    rating = @page.reactions.build(author: @page, score: Rating::LIKE)

    refute_predicate rating, :valid?
    assert_match(/own post/, rating.errors.full_messages.to_sentence)
    assert_equal 0, @page.reload.score
  end

  test "two people are worth two points" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    @page.reactions.create!(author: @other, score: Rating::LIKE)

    assert_equal 2, @page.score
  end

  test "an account's own reactions go with it when it closes" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    assert_equal 1, @page.score

    @visitor.destroy!

    assert_equal 0, @page.reload.score, "a closed account leaves no vote behind"
  end

  test "what a visitor said about a page can be looked up for the page to show" do
    @page.reactions.create!(author: @visitor, score: Rating::DISLIKE)

    assert_equal Rating::DISLIKE, @visitor.rating_for(@page)
    assert_nil @other.rating_for(@page)
  end

  # ── reacting to what was posted, not only to the page ────────────────────────────────────
  #
  # This is the change: the thing a person reacts to is the thing they were looking at. The
  # rice is separate from the page, and so is its score.

  test "the rice can be reacted to, and carries its own score" do
    rice = @page.create_showcase!(title: "my desk")

    rice.reactions.create!(author: @visitor, score: Rating::LIKE)

    assert_equal 1, rice.score
    assert_equal 0, @page.reactions.count, "the page's own reactions are still the page's own"
  end

  test "a page's score is the page plus everything posted on it" do
    rice = @page.create_showcase!(title: "my desk")
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    rice.reactions.create!(author: @other, score: Rating::LIKE)

    assert_equal 2, @page.score, "liking the rice on somebody's page lifts the page"
    assert_equal 1, rice.score, "and the rice keeps its own number"
    assert_equal 2, @page.likes
  end

  test "a page's tally counts a dislike of something posted on it" do
    build = @page.builds.create!(title: "the closet rack")
    build.reactions.create!(author: @visitor, score: Rating::DISLIKE)

    assert_equal(-1, @page.score)
    assert_equal 1, @page.dislikes
  end

  test "somebody cannot react to their own rice" do
    rice = @page.create_showcase!(title: "my desk")

    rating = rice.reactions.build(author: @page, score: Rating::LIKE)

    refute_predicate rating, :valid?
    assert_equal 0, rice.reload.score
  end

  test "the same account can react to the page and to the rice on it" do
    rice = @page.create_showcase!(title: "my desk")

    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    rice.reactions.create!(author: @visitor, score: Rating::LIKE)

    assert_equal 2, @page.score, "two different things, two opinions, both counted"
  end

  test "what a visitor said about one thing can be looked up without asking about the page" do
    rice = @page.create_showcase!(title: "my desk")
    rice.reactions.create!(author: @visitor, score: Rating::LIKE)

    assert_equal Rating::LIKE, @visitor.reaction_to(rice)
    assert_nil @visitor.reaction_to(@page)
  end
end
