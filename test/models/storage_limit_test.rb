# frozen_string_literal: true

require "test_helper"

# One ceiling for one account.
#
# The per-file limits (`ProfilePicture::MAX_BYTES` and friends) bound a single upload. These
# bound the account, which is a different question — and the point of the test is that the
# answer is the same whichever way the picture arrived. An earlier version of this kept the
# number in the API controller, so the studio's forms were unbounded: the same account could
# fill the disk by using the browser instead of the API. The cap is now `User::STORAGE_LIMIT`,
# checked by `CountedTowardStorage` on the records, and this is what says so.
#
# The account is filled by lowering the limit rather than by uploading megabytes: `with_limit`
# reaches the boundary without writing 200 MB of fixtures, and the arithmetic being tested —
# stored + adding against the limit, minus the picture being replaced — is identical.
class StorageLimitTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
  end

  test "an account with room keeps its pictures" do
    with_limit(10.kilobytes) do
      shot = attach_shot(1.kilobyte)

      assert_predicate shot, :persisted?
      assert_equal 1.kilobyte, @user.stored_picture_bytes
    end
  end

  test "the limit is on the account, so a rice shot past it is refused" do
    with_limit(2.kilobytes) do
      assert_predicate attach_shot(1.kilobyte), :persisted?

      shot = attach_shot(4.kilobytes)

      refute_predicate shot, :persisted?
      assert_match(/past its/, shot.errors.full_messages.to_sentence)
    end
  end

  test "a hardware photo counts against the same cap as a rice shot" do
    with_limit(2.kilobytes) do
      attach_shot(1.kilobyte)

      build = @user.builds.create!(title: "the bench")
      photo = build.photos.build
      photo.image.attach(blob_of(4.kilobytes))

      refute photo.save
      assert_match(/past its/, photo.errors.full_messages.to_sentence)
    end
  end

  test "the profile picture counts against the same cap" do
    with_limit(2.kilobytes) do
      attach_shot(1.kilobyte)

      picture = @user.build_profile_picture
      picture.image.attach(blob_of(4.kilobytes))

      refute picture.save
    end
  end

  test "the cap is checked on the record, so the studio's forms are bounded too" do
    # The studio attaches a picture and saves the record, exactly as this does. Nothing about
    # the path it arrives by is part of the check — that is the whole point of moving the
    # number onto the account, and this is the assertion that would have caught the version
    # where only the API enforced it.
    with_limit(1.kilobyte) do
      shot = @user.build_showcase.shots.build(caption: "from a form")
      shot.image.attach(blob_of(4.kilobytes))

      refute shot.save
    end
  end

  test "replacing a picture is not an account growing by two pictures" do
    with_limit(2.kilobytes) do
      assert_predicate attach_shot(1.kilobyte), :persisted?

      # A picture of the same size that replaces another must fit: the account is not larger.
      # Without the `excluding:` in `over_storage_limit?` an owner would be unable to change
      # their own screenshot once they were near the cap.
      shot = @user.showcase.shots.sole
      shot.image.attach(blob_of(1.kilobyte))

      assert shot.save
    end
  end

  test "everything the account stores is counted, wherever it lives" do
    with_limit(100.kilobytes) do
      attach_shot(1.kilobyte)

      build = @user.builds.create!(title: "the bench")
      photo = build.photos.build
      photo.image.attach(blob_of(2.kilobytes))
      photo.save!

      picture = @user.build_profile_picture
      picture.image.attach(blob_of(3.kilobytes))
      picture.save!

      # A count that missed one of the three places would not be a limit.
      assert_equal 6.kilobytes, @user.reload.stored_picture_bytes
    end
  end

  test "one picture over the per-file ceiling is refused before the account is even asked" do
    # The two ceilings are different questions: this is the file's own limit, which holds even
    # on an empty account.
    shot = @user.build_showcase.shots.build
    shot.image.attach(blob_of(ShowcaseShot::MAX_BYTES + 1))

    refute shot.save
    assert_match(/smaller than/, shot.errors.full_messages.to_sentence)
  end

  private
    # Lower the account's ceiling for one test and put it back afterwards. The constant is the
    # one number the models read, so replacing it is how the boundary is reached without
    # writing a real 200 MB of pictures.
    WITH_LIMIT_MUTEX = Mutex.new

    def with_limit(bytes)
      WITH_LIMIT_MUTEX.synchronize do
        original = User::STORAGE_LIMIT
        User.send(:remove_const, :STORAGE_LIMIT)
        User.const_set(:STORAGE_LIMIT, bytes)

        begin
          yield
        ensure
          User.send(:remove_const, :STORAGE_LIMIT)
          User.const_set(:STORAGE_LIMIT, original)
        end
      end
    end

    def attach_shot(bytes)
      shot = @user.build_showcase.shots.build(caption: "a shot")
      shot.image.attach(blob_of(bytes))
      shot.save
      shot
    end

    # A real image of exactly the size wanted: Active Storage identifies content, so the test
    # needs something that is actually a picture — and the sizes are the arithmetic under test,
    # so they have to be exact rather than roughly right. A 1x1 PNG is padded to the byte count
    # asked for; the model's own check reads the declared type and the blob's size.
    ONE_PIXEL_PNG = [ "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" ].pack("m0")

    def blob_of(bytes)
      raise ArgumentError, "ask for at least #{ONE_PIXEL_PNG.bytesize} bytes" if bytes < ONE_PIXEL_PNG.bytesize

      { io: StringIO.new(ONE_PIXEL_PNG + ("\0" * (bytes - ONE_PIXEL_PNG.bytesize))),
        filename: "rice.png", content_type: "image/png" }
    end
end
