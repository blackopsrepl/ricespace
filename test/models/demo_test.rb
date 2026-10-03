# frozen_string_literal: true

require "test_helper"

# The demoscene category: a demo is a release, not just a video, and its facts are the
# entry.
class DemoTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
  end

  def demo(attributes = {})
    @user.demos.build({ title: "A Demo" }.merge(attributes))
  end

  test "a demo is listed with its release facts" do
    record = demo(title: "fr-025: the.popular.demo", group_name: "Farbrausch",
      party: "Breakpoint", release_year: 2003, platform: "Windows", category: "64k intro", ranking: 1)

    assert_predicate record, :valid?
    assert_equal "Breakpoint 2003", record.release_note
    assert_equal "1st place", record.placing_note
  end

  test "a title is all that is required" do
    assert_predicate demo(title: "something"), :valid?

    refute_predicate demo(title: ""), :valid?
    refute_predicate @user.demos.build, :valid?
  end

  test "the placing is said the way it is spoken" do
    assert_equal "2nd place", demo(ranking: 2).placing_note
    assert_equal "3rd place", demo(ranking: 3).placing_note
    assert_equal "4th place", demo(ranking: 4).placing_note
    assert_equal "11th place", demo(ranking: 11).placing_note
    assert_nil demo.placing_note
  end

  test "the release note is whatever of the party and year is known" do
    assert_equal "Revision 2019", demo(party: "Revision", release_year: 2019).release_note
    assert_equal "1936", demo(release_year: 1936).release_note.to_s
    assert_nil demo.release_note
  end

  test "a year or a placing outside what is plausible is refused" do
    refute_predicate demo(release_year: 1700), :valid?
    refute_predicate demo(release_year: 3999), :valid?
    refute_predicate demo(ranking: 0), :valid?
    refute_predicate demo(ranking: -1), :valid?
  end

  test "the platform is a short vocabulary rather than free text" do
    assert_predicate demo(platform: "Amiga"), :valid?
    assert_predicate demo(platform: "C64"), :valid?
    assert_predicate demo(platform: ""), :valid?

    refute_predicate demo(platform: "a thing I have here"), :valid?
  end

  test "a demo whose link is a video embeds" do
    record = demo(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")

    assert_predicate record, :valid?
    assert_equal "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", record.embed[:src]
  end

  test "a demo whose link is a catalogue page is a link, not a broken frame" do
    record = demo(url: "https://www.pouet.net/prod.php?which=12345")

    assert_predicate record, :valid?
    assert_nil record.embed
    assert_equal "https://www.pouet.net/prod.php?which=12345", record.url
  end

  test "a link that is not an http address is refused" do
    [ "javascript:alert(1)", "not a url", "data:text/html,x", "https://user:pass@pouet.net/x" ].each do |bad|
      refute_predicate demo(url: bad), :valid?, "expected #{bad.inspect} to be refused"
    end
  end

  test "no link at all is fine — the release facts stand on their own" do
    assert_predicate demo(url: nil, group_name: "Conspiracy"), :valid?
  end

  test "demos are listed oldest first" do
    old = @user.demos.create!(title: "second", release_year: 1993)
    recent = @user.demos.create!(title: "first", release_year: 2019)
    undated = @user.demos.create!(title: "undated")

    assert_equal [ undated, old, recent ], @user.demos.in_order.to_a
  end

  test "deleting the account takes its demos" do
    @user.demos.create!(title: "a demo")

    assert_difference -> { Demo.count } => -1 do
      @user.destroy
    end
  end
end
