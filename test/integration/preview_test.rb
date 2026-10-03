# frozen_string_literal: true

require "test_helper"

# The folder preview.
#
# The whole reason this route exists rather than the CLI drawing the page itself: the rules
# about what survives are the site's, and the only way a preview cannot drift is to use them.
# So the test that matters here is not "does it render" but "does it strip what the site
# strips" — a preview that showed a `<script>` running would be worse than no preview, because
# a person would trust it.
class PreviewTest < ActionDispatch::IntegrationTest
  setup do
    @root = Rails.root.join("tmp", "preview", "test-#{SecureRandom.hex(4)}")
    FileUtils.mkdir_p(@root)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "a folder is drawn with its markup, its rice, and its lists" do
    write("page.html", "<h1>the bench</h1>")
    write("rice.json", { title: "the rice bench", summary: "the machine", theme: "synthwave" }.to_json)
    write("blurbs.json", [ { title: "Interests", body: "<b>rices</b>" } ].to_json)
    write("demos.json", [ { title: "second reality", group: "future crew" } ].to_json)
    write("friends.json", [ "ron" ].to_json)

    get preview_url(File.basename(@root))

    assert_response :success
    assert_match "the bench", response.body
    assert_match "the rice bench", response.body
    assert_match "synthwave", response.body
    assert_match "rices", response.body
    assert_match "second reality", response.body
    assert_match "ron", response.body
  end

  test "the preview strips what the site strips, so it cannot lie about the page" do
    write("page.html", "<marquee>kept</marquee><script>alert(1)</script><b onclick=\"evil()\">text</b>")

    get preview_url(File.basename(@root))

    assert_response :success
    # The tag the sanitizer allows survives.
    assert_match "<marquee>", response.body
    # The script, and the handler that rode in on an allowed tag, do not.
    refute_match "<script>alert", response.body
    refute_match "onclick", response.body
  end

  test "the author's stylesheet is applied" do
    write("page.html", "<style>body { color: #ff6ec7; }</style><p>styled</p>")

    get preview_url(File.basename(@root))

    assert_response :success
    assert_match "#ff6ec7", response.body
  end

  test "a folder that is not there says so rather than raising" do
    get preview_url("no-such-folder")

    assert_response :not_found
    assert_match "no folder", response.body
  end

  test "a folder cannot be reached by walking out of the preview directory" do
    get "/preview/..%2F..%2Fconfig"

    # Whatever the router does with it, the answer must not be the app's own files.
    refute_match "Rails.application.routes", response.body
  end

  private
    def write(name, body)
      @root.join(name).write(body)
    end
end
