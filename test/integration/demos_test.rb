# frozen_string_literal: true

require "test_helper"

# The demoscene category from the browser: an owner lists a demo, a visitor reads it.
class DemosTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "an owner lists a demo and it appears with its release facts" do
    post demos_url, params: { demo: {
      title: "fr-025: the.popular.demo", group_name: "Farbrausch", party: "Breakpoint",
      release_year: 2003, platform: "Windows", category: "64k intro", ranking: 1,
      url: "https://www.pouet.net/prod.php?which=12345", watch_note: "watch the end"
    } }

    assert_redirected_to studio_url

    get profile_url(@user)

    assert_response :success
    assert_match 'id="demos"', response.body
    assert_match "fr-025: the.popular.demo", response.body
    assert_match "Farbrausch", response.body
    assert_match "Breakpoint 2003", response.body
    assert_match "64k intro", response.body
    assert_match "1st place", response.body
    assert_match "pouet.net/prod.php?which=12345", response.body
  end

  test "a demo linked on YouTube is embedded, a catalogue link is not framed" do
    post demos_url, params: { demo: { title: "on a player", url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ" } }
    post demos_url, params: { demo: { title: "in a catalogue", url: "https://www.pouet.net/prod.php?which=1" } }

    get profile_url(@user)

    assert_match "www.youtube-nocookie.com/embed/dQw4w9WgXcQ", response.body
    refute_match "pouet.net\"", response.body
    # Framed once, not twice: the catalogue entry is a link.
    assert_equal 1, response.body.scan("<iframe").size
  end

  test "a demo is edited and removed" do
    post demos_url, params: { demo: { title: "a demo", release_year: 1993 } }
    record = @user.demos.sole

    patch demo_url(record), params: { demo: { ranking: 2 } }

    assert_redirected_to studio_url
    assert_equal 2, record.reload.ranking

    delete demo_url(record)

    assert_redirected_to studio_url
    assert_empty @user.demos
  end

  test "the studio offers the demoscene category" do
    get studio_url

    assert_response :success
    assert_match "Demos", response.body
    assert_match "Add demo", response.body
    assert_match "64k intro", response.body
  end

  test "a demo with no title is refused and says so" do
    post demos_url, params: { demo: { title: "" } }

    assert_redirected_to studio_url
    assert_match "Title can't be blank", flash[:alert]
    assert_empty @user.demos
  end
end
