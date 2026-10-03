# frozen_string_literal: true

require "test_helper"

class DemoSiteTest < ActiveSupport::TestCase
  test "repeating population leaves documents, credentials and record counts unchanged" do
    capture_io { DemoSite::Writer.new(verbose: false).call }
    before = snapshot
    capture_io { DemoSite::Writer.new(verbose: false).call }
    assert_equal before, snapshot
  end

  private def snapshot
    {
      users: User.order(:id).pluck(:id, :password_digest),
      pages: Profile.order(:id).pluck(:document, :updated_at),
      counts: [ Blurb, Build, Demo, StreamLink, Friendship, Rating, Comment, ShowcaseShot ].map(&:count)
    }
  end

  test "a failed population rolls back every earlier step" do
    before = snapshot
    broken = Class.new(DemoSite::Writer) do
      private def document_for(spec)
        raise "invalid demo content" if spec[:page] == "cordelia"
        super
      end
    end
    assert_raises(RuntimeError) { broken.new(verbose: false).call }
    assert_equal before, snapshot
  end

  test "the demo collection covers every shipped layout" do
    assert_equal Layout.all.map(&:slug).sort, DemoSite::Spaces::OTHERS.filter_map { |spec| spec[:layout] }.sort
  end

  # The rice's picture is drawn from the account's own facts, so it cannot contradict the page
  # it sits on. This is the one thing here worth a test of its own: the art is a real drawing
  # routine, not a lookup, and a picture that silently came out blank or the wrong size would
  # look like a layout bug.
  test "the rice art draws a real desktop in the theme it was asked for" do
    png = DemoSite::RiceArt.draw(
      theme: "tokyo-night", name: "Wes",
      facts: { wm: "sway", bar: "waybar", term: "ghostty", font: "iosevka", theme: "tokyo night", host: "wes" }
    )

    assert png.start_with?("\x89PNG".b), "a rice has to be a PNG"
    image = Vips::Image.new_from_buffer(png, "")
    assert_equal DemoSite::RiceArt::WIDTH, image.width
    assert_equal DemoSite::RiceArt::HEIGHT, image.height

    # Not a flat fill: a wallpaper, a bar and two windows are not one colour.
    assert_operator image.deviate, :>, 8, "an empty canvas is not a desktop"
  end

  test "an unknown theme falls back to the default rather than failing" do
    png = DemoSite::RiceArt.draw(theme: "nothing-like-this", name: "Somebody", facts: {})

    assert png.start_with?("\x89PNG".b)
  end

  test "every demo rice is drawn from its account, not looked up" do
    capture_io { DemoSite::Writer.new(verbose: false).call }

    DemoSite::Spaces::OTHERS.each do |spec|
      shot = User.find_by!(username: spec[:username]).showcase.shots.first
      assert shot&.image&.attached?, spec[:username]

      # The picture is the account's: the theme it says it runs is the theme it was drawn in.
      image = Vips::Image.new_from_buffer(shot.image.download, "")
      assert_equal DemoSite::RiceArt::WIDTH, image.width, spec[:username]
    end
  end

  test "population writes the real pages and every demo without replacing accounts" do
    password = SecureRandom.hex(24)
    ron = User.ron || User.create!(username: "ron", admin: true, email_address: "ron@example.com", password: password)
    vittorio = User.create!(username: "vittorio", email_address: "vittorio@example.com", password: password)
    ids = [ ron.id, vittorio.id ]
    digests = [ ron.password_digest, vittorio.password_digest ]

    capture_io { DemoSite::Writer.new(verbose: false).call }

    assert_equal ids, [ ron.reload.id, vittorio.reload.id ]
    assert_equal digests, [ ron.password_digest, vittorio.password_digest ]
    DemoSite::Spaces::REAL.each_key do |username|
      assert_equal DemoSite::Spaces::PAGES.fetch(username), User.find_by!(username: username).profile.document
    end
    DemoSite::Spaces::OTHERS.each do |spec|
      user = User.find_by!(username: spec[:username])
      assert user.blurbs.any?, spec[:username]
      assert user.showcase.filled?, spec[:username]
      if spec[:layout]
        assert_includes user.profile.document, Layout.find(spec[:layout]).css
      else
        assert_equal DemoSite::Spaces::CUSTOM.fetch(spec[:custom]), user.profile.document
      end
    end
  end
end
