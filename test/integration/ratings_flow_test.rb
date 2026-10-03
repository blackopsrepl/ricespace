# frozen_string_literal: true

require "test_helper"

# Rating a page over HTTP: the buttons on somebody's page, and the ranking on the front.
#
# The model tests pin the arithmetic; these pin what a visitor can actually do — including
# the parts a visitor is deliberately not able to do, which on this feature is most of it.
class RatingsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @page = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @visitor = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
  end

  test "a visitor likes a page" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_redirected_to profile_url(@page.username)
    assert_equal 1, @page.reload.score
  end

  test "pressing like twice takes the rating off again" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }
    assert_equal 1, @page.reload.score

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_equal 0, @page.reload.score
    assert_empty @page.ratings
  end

  test "liking then disliking moves the one rating rather than adding another" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }
    post rate_profile_url(@page.username), params: { score: Rating::DISLIKE }

    assert_equal(-1, @page.reload.score)
    assert_equal 1, @page.ratings.count
  end

  test "liking is signed in only" do
    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_redirected_to new_session_url
    assert_equal 0, @page.reload.score
  end

  test "an owner cannot rate their own page" do
    sign_in(@page)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_equal 0, @page.reload.score
    assert_not_nil flash[:alert]
  end

  test "a rating that is not a like or a dislike is refused" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: 99 }

    assert_equal 0, @page.reload.score
    assert_match(/not a rating/, flash[:alert])
  end

  test "a page shows its rating, and the visitor's own opinion on it" do
    @page.ratings.create!(author: @visitor, score: Rating::LIKE)
    sign_in(@visitor)

    get profile_url(@page.username)

    assert_response :success
    assert_select ".rating-value", text: "1"
    # Pressed already, so the button says so.
    assert_match "★ liked", response.body
  end

  test "the front page ranks by reaction, not by average" do
    # The case that decides it: a page a hundred people reacted to against a page one
    # person liked. By average the one-vote page wins and the controversial page is buried;
    # by reaction the page people actually reacted to leads. The second is the rule.
    quiet = User.create!(username: "quiet", email_address: "q@example.com", password: "correct horse battery")
    loud = User.create!(username: "loud", email_address: "w@example.com", password: "correct horse battery")

    quiet.ratings.create!(author: @page, score: Rating::LIKE)

    crowd = 6.times.map do |n|
      User.create!(username: "crowd#{n}", email_address: "c#{n}@example.com", password: "correct horse battery")
    end
    crowd.first(3).each { |person| loud.ratings.create!(author: person, score: Rating::LIKE) }
    crowd.last(3).each { |person| loud.ratings.create!(author: person, score: Rating::DISLIKE) }

    get root_url

    assert_response :success
    body = response.body
    assert_equal 0, loud.score, "the controversial page's net score is nothing"
    assert_equal 1, quiet.score
    assert body.index("@quiet") < body.index("@loud"),
      "a page with net +1 outranks a page with net 0, however reacted-to"
  end

  test "equal nets break ties on total reactions; unrated pages stay off" do
    unrated = User.create!(username: "unrated", email_address: "u@example.com", password: "correct horse battery")
    debated = User.create!(username: "debated", email_address: "d@example.com", password: "correct horse battery")

    @page.ratings.create!(author: @visitor, score: Rating::LIKE)
    debated.ratings.create!(author: @page, score: Rating::LIKE)
    debated.ratings.create!(author: @visitor, score: Rating::LIKE)
    debated.ratings.create!(author: unrated, score: Rating::DISLIKE)

    get root_url

    assert_response :success
    # Both rated pages are on the list with net +1; the more-discussed one leads.
    body = response.body
    assert body.index("@debated") < body.index("@vittorio"),
      "equal nets break toward the more-discussed page"
    assert_select "#popular a[href=?]", profile_path(unrated), count: 0
  end

  test "a visitor writes on somebody else's wall and on their own" do
    sign_in(@visitor)

    # Somebody else's page.
    post profile_comments_url(@page.username), params: { comment: { body: "nice rice" } }
    assert_equal 1, @page.reload.comments.count
    assert_equal @visitor, @page.comments.sole.author

    # Their own — the wall is not only for other people.
    post profile_comments_url(@visitor.username), params: { comment: { body: "hello my own wall" } }
    assert_equal 1, @visitor.reload.comments.count
    assert_equal @visitor, @visitor.comments.sole.author
  end

  test "posting on a wall is signed in only" do
    post profile_comments_url(@page.username), params: { comment: { body: "anonymous" } }

    assert_equal 0, @page.reload.comments.count
  end

  private
    def sign_in(user)
      post session_url, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
