# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "tmpdir"

require_relative "../lib/ricespace"

# The CLI's own tests: the parts that are decisions rather than plumbing. Everything here
# runs without a space — the client is the only thing that needs one, and it is not what
# these are about.
class RiceSpaceTest < Minitest::Test
  # ---- the terminal view ---------------------------------------------------------------

  def test_a_pipe_gets_plain_text_so_a_redirect_writes_a_file_not_a_file_full_of_escapes
    RiceSpace::Ui.styled = false

    out = capture_stdout { RiceSpace::Ui.wordmark }
    refute_includes out, "\e[", "a piped view must carry no escape codes"

    RiceSpace::Ui.styled = nil
  end

  def test_colour_is_used_only_when_something_is_a_terminal
    RiceSpace::Ui.styled = true
    coloured = capture_stdout { RiceSpace::Ui.ok("done") }
    assert_includes coloured, "\e["

    RiceSpace::Ui.styled = false
    plain = capture_stdout { RiceSpace::Ui.ok("done") }
    refute_includes plain, "\e["

    RiceSpace::Ui.styled = nil
  end

  def test_a_list_of_names_reads_as_names_and_not_as_records_with_a_value_field
    RiceSpace::Ui.styled = false

    out = capture_stdout { RiceSpace::Ui.list("friends", %w[ron bob]) }

    assert_includes out, "ron"
    assert_includes out, "bob"
    refute_includes out, "VALUE", "a friend is a name, not a record with one field"

    RiceSpace::Ui.styled = nil
  end

  def test_a_list_of_records_reads_as_labelled_facts
    RiceSpace::Ui.styled = false

    out = capture_stdout do
      RiceSpace::Ui.list("links", [ { "platform" => "youtube", "title" => "a video" } ])
    end

    assert_includes out, "PLATFORM"
    assert_includes out, "youtube"
    assert_includes out, "TITLE"

    RiceSpace::Ui.styled = nil
  end

  # ---- credentials ---------------------------------------------------------------------

  def test_a_token_is_shown_as_its_shape_and_never_its_value
    command = RiceSpace::Command.new([])
    token = "rs_0123456789abcdef0123456789abcdef0123456789abcdef"

    shown = command.send(:mask, token)

    refute_equal token, shown
    refute_includes shown, "0123456789abcdef"
    assert shown.start_with?("rs_0123")
    assert shown.end_with?("cdef")
    assert_equal "(not set)", command.send(:mask, "")
    assert_equal "rs_…", command.send(:mask, "short")
  end

  def test_a_folder_does_not_carry_the_token
    Dir.mktmpdir do |dir|
      folder = File.join(dir, "space")
      FileUtils.mkdir_p(folder)

      # The manifest is the only file that names the space, and it names the address only.
      token = "rs_deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
      out = capture_stdout do
        begin
          RiceSpace::Folder.write_out(folder, StubSpace.new(token))
        rescue RiceSpace::ApiError
          nil
        end
      end
      out # silence

      files = Dir.glob(File.join(folder, "**", "*"), File::FNM_DOTMATCH).select { |f| File.file?(f) }
      files.each do |file|
        refute_includes File.read(file), token, "#{file} must not hold the token"
      end
    end
  end

  # ---- the revision rule ---------------------------------------------------------------

  def test_a_push_on_a_stale_sidecar_is_refused_before_it_is_sent
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<p>hi</p>")
      File.write(File.join(dir, "page.html.ricespace"), JSON.generate({ "version" => 1 }))

      folder = RiceSpace::Folder.read(dir)
      space = StubSpace.new("rs_x", version: 9, document: "<p>other</p>")

      error = assert_raises(RiceSpace::ApiError) { folder.push(space) }
      assert_includes error.message, "moved since this folder was cloned"
    end
  end

  def test_force_sends_on_the_current_revision_rather_than_being_refused_by_a_stale_one
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<p>mine</p>")
      File.write(File.join(dir, "page.html.ricespace"), JSON.generate({ "version" => 1 }))

      folder = RiceSpace::Folder.read(dir)
      space = StubSpace.new("rs_x", version: 9, document: "<p>theirs</p>")

      done = folder.push(space, force: true)

      assert_equal 9, space.pushed_version, "--force must build on the revision that is current"
      assert done.any? { |line| line.include?("revision") }
    end
  end

  def test_a_folder_with_no_change_sends_nothing
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<p>same</p>")

      folder = RiceSpace::Folder.read(dir)
      space = StubSpace.new("rs_x", version: 4, document: "<p>same</p>")

      assert_empty folder.push(space)
      assert_nil space.pushed_version, "nothing changed, so nothing should have been sent"
    end
  end

  def test_a_folder_with_no_page_is_not_a_folder
    Dir.mktmpdir do |dir|
      error = assert_raises(RiceSpace::UsageError) { RiceSpace::Folder.read(dir) }
      assert_includes error.message, "not a space folder"
    end
  end

  # ---- the change signal ---------------------------------------------------------------

  def test_the_sidecar_does_not_move_the_watch_stamp
    # A push writes `page.html.ricespace`. If the stamp counted it, every push would look
    # like the change it just made and `watch` would push in a loop of its own making.
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<p>hi</p>")
      command = RiceSpace::Command.new([])

      before = command.send(:folder_stamp, Pathname.new(dir))
      File.write(File.join(dir, "page.html.ricespace"), JSON.generate({ "version" => 2 }))
      assert_equal before, command.send(:folder_stamp, Pathname.new(dir))

      File.write(File.join(dir, "page.html"), "<p>hi there</p>")
      refute_equal before, command.send(:folder_stamp, Pathname.new(dir)),
        "an edit must still move the stamp"
    end
  end

  # ---- completions ---------------------------------------------------------------------

  def test_completions_cover_every_command_the_help_offers
    %w[bash zsh fish].each do |shell|
      text = RiceSpace::Completions.for(shell)
      RiceSpace::Completions::COMMANDS.each do |command|
        assert_includes text, command, "#{shell} completions must know #{command}"
      end
    end
  end

  def test_an_unknown_shell_is_refused_with_the_ones_that_work
    error = assert_raises(RiceSpace::UsageError) { RiceSpace::Completions.for("powershell") }
    assert_includes error.message, "bash, zsh or fish"
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end

# A Space that answers without a server, for the folder tests. Only the handful of methods
# the folder calls, so a change to the real client's surface shows up here as a failure.
class StubSpace
  attr_reader :pushed_version

  def initialize(token, version: 1, document: "")
    @token = token
    @version = version
    @document = document
  end

  def base = "http://example.test"

  def page
    { "username" => "stub", "url" => "http://example.test/profiles/stub",
      "document" => @document, "version" => @version, "html" => "", "css" => "" }
  end

  def rice = { "shots" => [] }

  def lists = { "page" => { "blurbs" => [], "demos" => [], "builds" => [], "links" => [], "friends" => [] } }

  def push(document, version)
    @pushed_version = version
    @document = document
    @version += 1
    page
  end

  def set_rice(_changes) = rice
  def set_lists(_changes) = lists
  def fetch_bytes(_url) = "".b
  def upload_image(*) = {}
end
