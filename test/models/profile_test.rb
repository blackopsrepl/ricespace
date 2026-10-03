# frozen_string_literal: true

require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "a new account's profile is an empty page" do
    profile = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery").profile

    assert_equal "", profile.document
    assert_equal "", profile.rendered.html.to_s
    assert_equal "", profile.rendered.css
  end

  test "the stored document is what the author wrote" do
    profile = create_profile

    assert_includes profile.document, "<marquee"
    assert_includes profile.reload.document, "<marquee"
  end

  test "the page is cleaned on read, so existing pages follow tightened rules" do
    profile = create_profile(document: %(<p>hi</p><script>alert(1)</script>))

    assert_includes profile.rendered.html, "<p>hi</p>"
    refute_includes profile.rendered.html, "alert(1)"
    assert_includes profile.reload.document, "alert(1)"
  end

  test "a profile's stylesheet comes back with its markup" do
    profile = create_profile(document: %(<style>body { background: #000 }</style><p>hi</p>))
    rendered = profile.rendered

    assert_includes rendered.css, "background: #000"
    refute_includes rendered.html, "<style"
    assert_predicate rendered.html, :html_safe?
  end

  test "a page cannot be stored unbounded" do
    profile = create_profile
    profile.document = "x" * (Profile::MAX_DOCUMENT_LENGTH + 1)

    refute_predicate profile, :valid?
    assert profile.errors[:document].any?
  end

  test "every change of content is a new revision" do
    profile = create_profile

    assert_equal 1, profile.reload.version

    profile.update!(document: "<p>changed</p>")
    assert_equal 2, profile.reload.version

    # A write that does not touch the document does not invent a revision, so an
    # editor is not told the page moved when it did not.
    profile.update!(updated_at: Time.current)
    assert_equal 2, profile.reload.version
  end

  test "a writer can tell whether the page moved since it read it" do
    profile = create_profile
    stale = profile.version
    Profile.find(profile.id).update!(document: "<p>moved</p>")

    refute_equal stale, profile.reload.version
  end

  test "a profile has no meaning without an account" do
    assert_not Profile.new(document: "<p>x</p>").valid?
  end

  private
    def create_profile(document: %(<marquee>welcome to my page</marquee>))
      user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
      user.profile.tap { |profile| profile.update!(document: document) }
    end
end
