# frozen_string_literal: true

require "test_helper"
require "capybara/rails"
require "capybara/minitest"
require "selenium-webdriver"

# A real browser, because the last three bugs in this area were all invisible to a
# request test. `script_loading_test.rb` proves the nonce is in the header *and* on
# every inline script; only a browser can prove the scripts therefore run, which is
# the thing that was broken: with `script-src 'self'` and no nonce the whole client
# side was dead, and the confirmation on closing an account never appeared.
#
# This is the loop-closer, not the guard — it is slow, so it runs with `bin/rails
# test:system` and stays out of the main suite and `bin/ci`.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # The lab's chromium is a system package; the driver comes from Selenium
    # Manager, which caches it under ~/.cache/selenium. `--no-sandbox` because the
    # suite runs unprivileged.
    options.binary = ENV.fetch("CHROMIUM_BINARY", "/usr/bin/chromium")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end

  # Signing in is rate limited per client and every request here comes from one, so
  # every test that needs a session goes through here. `sign_in_as` would be a nice
  # name; it is the one `account_lifecycle_test.rb` already uses for a request test,
  # and this is not that.
  def signed_in_as(user)
    ApplicationController::RATE_LIMIT_STORE.clear
    visit new_session_path

    # The header carries a "Sign in" link and the form a "Sign in" button, so the
    # form's own fields are what to aim at.
    within "form" do
      fill_in "email_address", with: user.email_address
      fill_in "password", with: user.password
      click_on "Sign in"
    end

    # Sign-in is a POST through Turbo now that Turbo actually loads, and `click_on`
    # returns as soon as the click is dispatched — the redirect, and with it the
    # session cookie, lands a moment later. Waiting for the studio keeps the next
    # request from being made as a visitor, which is what made these tests look like
    # the button had gone missing.
    assert_current_path studio_path
    assert_text "Signed in as"
  end
end
