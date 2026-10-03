# frozen_string_literal: true

require "test_helper"

# The pictures, over the API.
#
# This is the path a folder uses to put a screenshot on a page: `clone` brings the bytes down
# into `assets/`, and `push` sends them back. It exists because a folder that names a picture
# but cannot carry one is not a folder that holds the page — and because the alternative, a
# person re-uploading through the studio every time, is not a workflow.
class ApiV1ImagesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "vittorio", email_address: "v@example.com", password: "correct horse battery")
    @token = AgentToken.issue(user: @user, name: "the CLI")
    @headers = { "Authorization" => "Bearer #{@token.plaintext}" }
  end

  test "a shot is uploaded and appears on the rice" do
    post api_v1_images_url, headers: @headers, params: { kind: "shot", caption: "the bench", file: image }

    assert_response :created
    shot = response.parsed_body["shot"]

    assert_equal "the bench", shot["caption"]
    assert_predicate shot["bytes"], :positive?
    assert @user.showcase.shots.sole.image.attached?
  end

  test "the profile picture is uploaded and the page reports it" do
    post api_v1_images_url, headers: @headers, params: { kind: "picture", file: image }

    assert_response :created
    assert_predicate @user.reload.profile_picture.image, :attached?

    get api_v1_page_url, headers: @headers

    assert_response :success
    assert_predicate response.parsed_body["page"]["picture"], :present?
  end

  test "a hardware photo is uploaded to the build its title names" do
    @user.builds.create!(title: "the bench", kind: "desktop")

    post api_v1_images_url, headers: @headers, params: { kind: "build", record: "the bench", file: image }

    assert_response :created
    assert_equal 1, @user.builds.sole.photos.count
  end

  test "a hardware photo with no build of that title is refused, and nothing is written" do
    post api_v1_images_url, headers: @headers, params: { kind: "build", record: "nothing", file: image }

    assert_response :not_found
    assert_equal "unknown_record", response.parsed_body["error"]["code"]
    assert_empty @user.builds
  end

  test "a shot's order is set whole, in one request, by the folder's order" do
    ids = 3.times.map { |i| post_shot("shot-#{i}") }

    patch api_v1_images_order_url, headers: @headers, params: { kind: "shot", ids: [ ids[2], ids[0], ids[1] ] }

    assert_response :success
    order = response.parsed_body["shots"].map { |shot| shot["id"] }

    assert_equal [ ids[2], ids[0], ids[1] ], order
    assert_equal order, @user.showcase.reload.shots.map(&:id)
  end

  test "a picture that is not an image is refused rather than stored" do
    post api_v1_images_url, headers: @headers, params: { kind: "shot", file: text_file }

    assert_response :unprocessable_content
    assert_equal "invalid_image", response.parsed_body["error"]["code"]
    assert_nil @user.showcase
  end

  test "an upload with no file says so" do
    post api_v1_images_url, headers: @headers, params: { kind: "shot" }

    assert_response :bad_request
    assert_equal "missing_file", response.parsed_body["error"]["code"]
  end

  test "a shot is removed by its id" do
    id = post_shot("temporary")

    delete api_v1_image_url(id), headers: @headers, params: { kind: "shot" }

    assert_response :no_content
    assert_empty @user.showcase.reload.shots
  end

  test "the images endpoint needs a token" do
    post api_v1_images_url, params: { kind: "shot", file: image }

    assert_response :unauthorized
  end

  private
    # A real PNG, because Active Storage identifies content rather than trusting a name.
    def image(filename = "rice.png")
      Rack::Test::UploadedFile.new(Rails.root.join("test", "fixtures", "files", "rice.png"), "image/png",
        original_filename: filename)
    end

    def text_file
      path = Rails.root.join("tmp", "api-not-an-image.txt")
      path.write("this is not an image")
      Rack::Test::UploadedFile.new(path, "text/plain", original_filename: "payload.txt")
    end

    def post_shot(caption)
      post api_v1_images_url, headers: @headers, params: { kind: "shot", caption: caption, file: image }

      assert_response :created
      response.parsed_body["shot"]["id"]
    end
end
