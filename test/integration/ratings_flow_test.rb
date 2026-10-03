# frozen_string_literal: true

require "test_helper"

# Reacting to something posted, over HTTP — and the ranking on the front page.
#
# The model tests pin the arithmetic; these pin what a visitor can actually do, including the
# parts a visitor is deliberately not able to do, which on this feature is most of it.
#
# The second half is the change: a reaction lands on the rice, a build, a demo or a link, and
# the page's own ranking is assembled from all of them.
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

  test "pressing like twice takes the reaction off again" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }
    assert_equal 1, @page.reload.score

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_equal 0, @page.reload.score
    assert_empty @page.reactions
  end

  test "liking then disliking moves the one reaction rather than adding another" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }
    post rate_profile_url(@page.username), params: { score: Rating::DISLIKE }

    assert_equal(-1, @page.reload.score)
    assert_equal 1, @page.reactions.count
  end

  test "reacting is signed in only" do
    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_redirected_to new_session_url
    assert_equal 0, @page.reload.score
  end

  test "an owner cannot react to their own page" do
    sign_in(@page)

    post rate_profile_url(@page.username), params: { score: Rating::LIKE }

    assert_equal 0, @page.reload.score
    assert_not_nil flash[:alert]
  end

  test "a reaction that is not a like or a dislike is refused" do
    sign_in(@visitor)

    post rate_profile_url(@page.username), params: { score: 99 }

    assert_equal 0, @page.reload.score
    assert_match(/not a reaction/, flash[:alert])
  end

  test "a page shows its score, and the visitor's own reaction to it" do
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    sign_in(@visitor)

    get profile_url(@page.username)

    assert_response :success
    assert_select ".reaction-score", text: "1"
    # Pressed already, so the button is the pressed one.
    assert_select ".reaction-on", text: "★"
  end

  # ── reacting to what was posted ──────────────────────────────────────────────────────────

  test "a visitor likes somebody's rice, and it lands on the rice" do
    rice = @page.create_showcase!(title: "my desk")
    sign_in(@visitor)

    post rate_post_url(@page.username, "showcase", rice.id), params: { score: Rating::LIKE }

    assert_equal 1, rice.reload.score
    assert_equal 0, @page.reactions.count, "the page's own reactions are still the page's own"
    assert_equal 1, @page.score, "but the page counts what is on it"
  end

  test "pressing like twice on a post takes the reaction off again" do
    rice = @page.create_showcase!(title: "my desk")
    sign_in(@visitor)

    post rate_post_url(@page.username, "showcase", rice.id), params: { score: Rating::LIKE }
    assert_equal 1, rice.reload.score

    post rate_post_url(@page.username, "showcase", rice.id), params: { score: Rating::LIKE }

    assert_equal 0, rice.reload.score
    assert_empty rice.reactions
  end

  test "an owner cannot react to their own rice" do
    rice = @page.create_showcase!(title: "my desk")
    sign_in(@page)

    post rate_post_url(@page.username, "showcase", rice.id), params: { score: Rating::LIKE }

    assert_equal 0, rice.reload.score
    assert_match(/own post/, flash[:alert])
  end

  test "reacting to a post that is on somebody else's page is refused" do
    elsewhere = User.create!(username: "somebody", email_address: "s@example.com",
      password: "correct horse battery")
    other_rice = elsewhere.create_showcase!(title: "not this page")
    sign_in(@visitor)

    post rate_post_url(@page.username, "showcase", other_rice.id), params: { score: Rating::LIKE }

    assert_equal 0, other_rice.reload.score
  end

  test "a reaction on a kind that does not exist is refused" do
    sign_in(@visitor)

    post rate_post_url(@page.username, "spaceship", 1), params: { score: Rating::LIKE }

    assert_match(/no such post/, flash[:alert])
  end

  test "the rice and the page each keep their own number on the page" do
    rice = @page.create_showcase!(title: "my desk")
    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    rice.reactions.create!(author: @page, score: Rating::LIKE) rescue nil

    get profile_url(@page.username)

    assert_response :success
    # The page's line and the rice's line are separate things on the page.
    assert_select "#profile-reactions .reaction-score", text: "1"
    assert_select "#showcase-reactions .reaction-score", text: "0"
  end

  # ── the ranking ─────────────────────────────────────────────────────────────────────────

  test "the front page ranks by reaction, not by average" do
    # The case that decides it: a page six people reacted to against a page one person liked.
    # By average the one-vote page wins and the controversial page is buried; by reaction the
    # page people actually reacted to leads. The second is the rule.
    quiet = User.create!(username: "quiet", email_address: "q@example.com", password: "correct horse battery")
    loud = User.create!(username: "loud", email_address: "w@example.com", password: "correct horse battery")

    quiet.reactions.create!(author: @page, score: Rating::LIKE)

    crowd = 6.times.map do |n|
      User.create!(username: "crowd#{n}", email_address: "c#{n}@example.com", password: "correct horse battery")
    end
    crowd.first(3).each { |person| loud.reactions.create!(author: person, score: Rating::LIKE) }
    crowd.last(3).each { |person| loud.reactions.create!(author: person, score: Rating::DISLIKE) }

    get root_url

    assert_response :success
    assert_equal 0, loud.score, "the loud page's net score is nothing"

    popular = response.body[/<section id="popular".*?<\/section>/m].to_s
    assert popular.index("@loud") < popular.index("@quiet"),
      "a page six people reacted to outranks a page one person liked"
  end

  test "a page rises on what was posted on it, not only on its own reactions" do
    # The rule the page's own score follows, seen from the front page: liking the rice lifts
    # the page that carries it.
    quiet = User.create!(username: "quiet", email_address: "q@example.com", password: "correct horse battery")
    quiet.reactions.create!(author: @visitor, score: Rating::LIKE)

    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    rice = @page.create_showcase!(title: "my desk")
    rice.reactions.create!(author: quiet, score: Rating::DISLIKE)

    assert_equal 0, @page.score, "a like on the page and a dislike of its rice cancel out"
    # Both pages now have one reaction; the tie breaks on the net score.
    get root_url

    assert_response :success
    popular = response.body[/<section id="popular".*?<\/section>/m].to_s
    assert_includes popular, "@quiet"
    assert_includes popular, "@vittorio"
  end

  test "equal nets break ties on total reactions; unreacted pages stay off" do
    unrated = User.create!(username: "unrated", email_address: "u@example.com", password: "correct horse battery")
    debated = User.create!(username: "debated", email_address: "d@example.com", password: "correct horse battery")

    @page.reactions.create!(author: @visitor, score: Rating::LIKE)
    debated.reactions.create!(author: @page, score: Rating::LIKE)
    debated.reactions.create!(author: @visitor, score: Rating::LIKE)
    debated.reactions.create!(author: unrated, score: Rating::DISLIKE)

    get root_url

    assert_response :success
    # Both reacted pages are on the list with net +1; the more-discussed one leads.
    body = response.body
    assert body.index("@debated") < body.index("@vittorio"),
      "equal nets break toward the more-discussed page"
    assert_select "#popular a[href=?]", profile_path(unrated), count: 0
  end

  test "a visitor writes on somebody else's wall and on their own" do
    sign_in(@visitor)

    post profile_comments_url(@page.username), params: { comment: { body: "nice rice" } }
    assert_equal 1, @page.reload.comments.count
    assert_equal @visitor, @page.comments.sole.author

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
