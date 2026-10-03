# frozen_string_literal: true

require "application_system_test_case"

# The site's own JavaScript, run by a browser.
#
# The failure these pin is not a rendering bug: with `script-src 'self'` and no nonce
# generator, every script the layout ships was blocked, Turbo never loaded, and
# `data-turbo-confirm` — the confirmation on closing an account — silently did
# nothing. A request test cannot see any of that, because the HTML looks correct.
class ScriptLoadingSystemTest < ApplicationSystemTestCase
  TEST_PASSWORD = "correct horse battery"

  setup do
    @user = User.create!(username: "cordelia", email_address: "c@example.com",
      password: TEST_PASSWORD, name: "Cordelia")
  end

  test "the client side loads: Turbo and Stimulus are running" do
    visit root_path

    assert_equal "object", evaluate_script("typeof window.Turbo"),
      "Turbo did not load — the importmap or the module entry point was blocked"
    assert_equal "object", evaluate_script("typeof window.Stimulus")
  end

  test "closing an account asks first, and a refusal keeps the account" do
    signed_in_as @user
    visit studio_path

    # Turbo hands `data-turbo-confirm` to the browser's own confirm dialog. Dismissing
    # it has to stop the request; anything else means the button deletes on the click.
    dismiss_confirm do
      click_on "Delete my account and everything on it"
    end

    assert_current_path studio_path
    assert User.exists?(@user.id), "the account was deleted without a confirmation"
    assert_text "Studio"
  end

  test "the confirmation names the account and says it does not undo" do
    signed_in_as @user
    visit studio_path

    message = accept_confirm do
      click_on "Delete my account and everything on it"
    end

    assert_match "@cordelia", message
    assert_match "does not undo", message

    # Accepting does go through, so the dialog is not a dead end.
    assert_current_path root_path
    refute User.exists?(@user.id)
  end

  test "wearing a layout asks first and says it keeps your own rules" do
    signed_in_as @user
    visit layouts_path

    # The index shows a card per layout, so every card carries its own button.
    message = accept_confirm do
      click_on "Wear this layout", match: :first
    end

    assert_match "stays yours", message, "the wear confirmation never named what it does"
  end

  test "taking another profile's layout asks first and says it replaces your rules" do
    other = User.create!(username: "taker", email_address: "t@example.com",
      password: TEST_PASSWORD, name: "Taker")
    other.profile.update!(document: "<style>body { background-color: #000 }</style>")
    signed_in_as @user
    visit profile_path(other)

    message = accept_confirm do
      click_on "Take this layout"
    end

    assert_match "replaces your own rules", message, "the take confirmation never named what it does"

    # The write happens in the app's own request thread, so the redirect (and its
    # flash) is the moment the copy has landed; reading the row before it is a race,
    # not a failure.
    assert_text "It is yours to edit now"
    assert_includes @user.profile.reload.document.to_s, "background-color",
      "accepting the confirmation did not take the layout"
  end

  test "the profile song starts on the first interaction" do
    @user.profile.update!(song_title: "a modem song", song_url: "https://example.com/modem.mp3")

    visit profile_path(@user)
    assert_selector "audio.song"

    # The module attaches a one-shot listener on the first pointer or key event and
    # calls play(). Before the fix the module never ran, so the listener was never
    # there and nothing was ever asked to play.
    played = evaluate_script(<<~JS)
      (() => {
        const heard = [];
        const real = HTMLMediaElement.prototype.play;
        HTMLMediaElement.prototype.play = function () { heard.push("play"); return Promise.resolve(); };
        document.dispatchEvent(new PointerEvent("pointerdown"));
        HTMLMediaElement.prototype.play = real;
        return heard;
      })()
    JS

    assert_equal [ "play" ], played,
      "the song module never ran — nothing tried to start the track"
  end
end
