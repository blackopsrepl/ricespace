# frozen_string_literal: true

require "test_helper"

class ShowcaseTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @showcase = @user.create_showcase(title: "Catppuccin on the Framework")
  end

  test "the facts are the ones that were filled in, in their own order" do
    @showcase.update!(theme: "catppuccin", terminal: "ghostty")

    assert_equal [ [ "terminal", "ghostty" ], [ "theme", "catppuccin" ] ], @showcase.facts
  end

  test "an empty showcase is not filled in, and a described one is" do
    blank = Showcase.new

    refute_predicate blank, :filled?

    @showcase.update!(summary: "a rice")

    assert_predicate @showcase, :filled?
  end

  test "a screenshot on its own is enough to be worth showing" do
    @showcase.update!(title: nil)
    shot = @showcase.shots.create!
    shot.image.attach(io: Rails.root.join("test", "fixtures", "files", "rice.png").open,
      filename: "rice.png", content_type: "image/png")

    assert_predicate @showcase.reload, :filled?
  end

  test "the cover is the first shot that actually has a picture" do
    without = @showcase.shots.create!
    with = @showcase.shots.create!
    with.image.attach(io: Rails.root.join("test", "fixtures", "files", "rice.png").open,
      filename: "rice.png", content_type: "image/png")

    assert_equal with, @showcase.reload.cover
    assert_equal 2, @showcase.shots.size
  end

  test "the details are markup, cleaned the same way a page's markup is" do
    @showcase.update!(details: %(<p>ghostty, <b>waybar</b></p><script>alert(1)</script>))

    assert_includes @showcase.rendered_details, "<b>waybar</b>"
    refute_includes @showcase.rendered_details, "<script"
  end

  test "a title or details over the limit is refused" do
    refute_predicate @showcase.tap { |s| s.title = "x" * (Showcase::MAX_LINE_LENGTH + 1) }, :valid?
    refute_predicate @showcase.tap { |s| s.details = "x" * (Showcase::MAX_DETAILS_LENGTH + 1) }, :valid?
  end

  test "one account has one showcase" do
    # A fresh record rather than `@user.build_showcase`: the uniqueness read is cached
    # per unit of work, and a record built through the association can be answered from
    # that cache. `Showcase.new(user_id:)` is the deterministic form.
    duplicate = Showcase.new(user_id: @user.id)

    refute_predicate duplicate, :valid?
    assert_match "already been taken", duplicate.errors.full_messages.to_s
  end

  test "the database, not just the model, refuses a second showcase for one account" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Showcase.new(user_id: @user.id).save!(validate: false)
    end
  end

  test "deleting the account takes the showcase and its shots" do
    @showcase.shots.create!

    assert_difference -> { Showcase.count } => -1, -> { ShowcaseShot.count } => -1 do
      @user.destroy
    end
  end
end
