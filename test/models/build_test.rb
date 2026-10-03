# frozen_string_literal: true

require "test_helper"

class BuildTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @build = @user.builds.create!(title: "The rack in the spare room")
  end

  def photo(build = @build, caption: nil)
    record = build.photos.build(caption: caption)
    record.image.attach(io: Rails.root.join("test", "fixtures", "files", "rice.png").open,
      filename: "photo.png", content_type: "image/png")
    record.save!
    record
  end

  test "a build is a title and whatever else is known" do
    assert_predicate @build, :valid?
    refute_predicate @user.builds.build, :valid?
  end

  test "the kind is a vocabulary, because a list of builds should be readable" do
    @build.update!(kind: "rack")

    assert_predicate @build, :valid?
    assert_equal "rack", @build.kind_label

    refute_predicate @build.tap { |b| b.kind = "a pile of things" }, :valid?
  end

  test "the facts are the ones filled in, and a kind is shown by its name" do
    @build.update!(kind: "server", specs: "Ryzen 9, 128 GB", cooling: "Noctua NH-D15")

    assert_equal [ [ "kind", "server" ], [ "specs", "Ryzen 9, 128 GB" ], [ "cooling", "Noctua NH-D15" ] ],
      @build.facts
  end

  test "an empty build has no facts to show" do
    assert_empty @build.facts
  end

  test "the details are markup, cleaned the same way a page's is" do
    @build.update!(details: "<p>loud</p><script>alert(1)</script>")

    assert_includes @build.rendered_details, "<p>loud</p>"
    refute_includes @build.rendered_details, "<script"
  end

  test "the cover is the first photo that actually has a picture" do
    blank = @build.photos.create!
    with = photo(caption: "the front")

    assert_equal with, @build.reload.cover
    assert_equal 2, @build.photos.size
    assert_predicate blank, :persisted?
  end

  test "photos are appended in order" do
    first = photo
    second = photo

    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "a photo that is not an image, or too large, is refused" do
    bad = @build.photos.build
    bad.image.attach(io: StringIO.new("not an image"), filename: "x.txt", content_type: "text/plain")

    refute_predicate bad, :valid?

    big = @build.photos.build
    big.image.attach(io: StringIO.new("0" * (BuildPhoto::MAX_BYTES + 1)), filename: "big.png",
      content_type: "image/png")

    refute_predicate big, :valid?
  end

  test "a page can carry several builds, unlike the rice" do
    @user.builds.create!(title: "a second one")

    assert_equal 2, @user.builds.count
  end

  test "builds are listed newest first" do
    older = @user.builds.create!(title: "older")
    older.update_column(:created_at, 2.days.ago)

    assert_equal [ @build.id, older.id ], @user.builds.in_order.map(&:id)
  end

  test "deleting the account takes its builds and their photos" do
    photo

    assert_difference -> { Build.count } => -1, -> { BuildPhoto.count } => -1 do
      @user.destroy
    end
  end
end
