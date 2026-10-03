# frozen_string_literal: true

require "test_helper"

# The site's CSP and the scripts the layout emits have to agree, and nothing else
# checks that they do.
#
# Every script the site ships is inline — the importmap and the module entry point in
# `layouts/application.html.erb` — and the policy is `script-src 'self'`, which blocks
# inline scripts unless each one carries a nonce. With no nonce generator configured the
# nonce is empty on both sides, so the whole client side is dead: Turbo never loads, and
# everything that depends on it goes with it. The expensive case is `data-turbo-confirm`
# on closing an account — the confirmation the studio promises is never shown, and the
# account is deleted on the click.
#
# So this asserts the pairing rather than any single symptom: a nonce in the header,
# the same nonce on every inline script, and no inline script without one. What it
# cannot prove is that a browser runs the result; `test/system/script_loading_test.rb`
# loads the page and asks whether Turbo is there.
class ScriptLoadingTest < ActionDispatch::IntegrationTest
  test "the policy carries a nonce and every inline script wears it" do
    get root_url
    assert_response :success

    policy = response.headers["content-security-policy"]
    assert policy.present?, "no content-security-policy header"

    nonce = policy[/script-src[^;]*'nonce-([^']+)'/, 1]
    assert nonce.present?, "script-src carries no nonce: #{policy}"

    scripts = Nokogiri::HTML(response.body).css("script")
    inline = scripts.reject { |script| script["src"] }

    # The importmap, the module entry point importmap-rails writes for it, and the
    # profile-song module written out by hand in the layout.
    assert_equal 3, inline.size,
      "expected the importmap, its entry point and the song module, got #{inline.size} inline scripts"
    assert_equal 1, inline.count { |script| script["type"] == "importmap" }

    inline.each do |script|
      assert_equal nonce, script["nonce"],
        "an inline script has no nonce and cannot run: #{script.to_html.truncate(120)}"
    end
  end

  test "a fresh nonce is issued per request" do
    get root_url
    first = response.headers["content-security-policy"][/'nonce-([^']+)'/, 1]

    get root_url
    second = response.headers["content-security-policy"][/'nonce-([^']+)'/, 1]

    refute_equal first, second, "the nonce is reused across requests"
  end

  test "the signed-in chrome is covered too" do
    user = User.create!(username: "cordelia", email_address: "c@example.com",
      password: "correct horse battery", name: "Cordelia")

    sign_in_as user

    get studio_url
    assert_response :success

    nonce = response.headers["content-security-policy"][/'nonce-([^']+)'/, 1]
    assert nonce.present?

    # The studio is where the irreversible action lives, so the page that carries it is
    # the one the pairing most needs to hold on.
    confirm = Nokogiri::HTML(response.body).at_css("[data-turbo-confirm]")
    assert confirm, "the account panel carries no confirmation for Turbo to fire"
    assert_match "does not undo", confirm["data-turbo-confirm"]

    Nokogiri::HTML(response.body).css("script:not([src])").each do |script|
      assert_equal nonce, script["nonce"]
    end
  end

  private
    def sign_in_as(user)
      ApplicationController::RATE_LIMIT_STORE.clear
      post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
