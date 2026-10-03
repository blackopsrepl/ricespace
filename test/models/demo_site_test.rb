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
