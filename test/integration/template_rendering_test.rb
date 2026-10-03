# frozen_string_literal: true

require "test_helper"

# Every template must render, not merely compile.
#
# Two failures this catches that nothing else does, both invisible in a diff and
# both fatal only at request time: a mangled keyword argument (`class:` written to
# disk as `class=`) and a helper call the template's own locals do not support.
# Compiling a template's Ruby is not enough — what matters is that Rails can render
# it — so this asks Rails to render each one against an integration session built
# for the purpose.
class TemplateRenderingTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com",
      password: "correct horse battery", name: "Vittorio Distefano", greeting: "welcome")
    @user.profile.update!(document: "<p>hi</p>")
    @user.blurbs.create!(title: "Interests", body: "<p>modems</p>")
    post session_url, params: { email_address: @user.email_address, password: "correct horse battery" }
  end

  test "the pages that render user data render" do
    paths = [ root_path, agents_path, agents_markdown_path, studio_path, new_session_path,
      new_registration_path, profile_path(@user) ]

    failures = paths.filter_map do |path|
      get(path)
      "#{path} -> #{response.status}" unless response.status.between?(200, 399)
    end

    assert_empty failures, "pages that did not render:\n#{failures.join("\n")}"
  end

  test "the studio offers the page's bits" do
    get studio_path

    assert_response :success
    assert_match "Your page's bits", response.body
    assert_match "Interests", response.body
    assert_match "Upload picture", response.body
  end

  test "a blurb, a friend and a comment all appear on the page" do
    friend = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @user.friendships.create!(friend: friend)
    @user.comments.create!(author: friend, body: "nice page")

    get profile_path(@user)

    assert_response :success
    assert_match "Interests", response.body
    assert_match "cordelia", response.body
    assert_match "nice page", response.body
  end

  test "the page carries the hook names a pasted layout targets" do
    friend = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
    @user.friendships.create!(friend: friend)
    @user.comments.create!(body: "hi", author_name: "a visitor")

    get profile_path(@user)

    %w[contactTable profile-pic contactInfo nametext orangetext15 blurb friendSpace
      top8 friend comments comment-body].each do |hook|
      assert_match hook, response.body, "expected the page to carry .#{hook}"
    end
  end
end
