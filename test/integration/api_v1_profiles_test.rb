# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    # The contract a coding agent codes against. These tests are the executable
    # half of docs/agent-contract.md: token auth, reading the page, writing the
    # page, and the failure modes an agent must handle rather than crash on.
    class ProfilesTest < ActionDispatch::IntegrationTest
      setup do
        @user = User.create!(username: "vittorio", email_address: "vittorio@example.com", password: "correct horse battery")
        @token = AgentToken.issue(user: @user, name: "claude code")
      end

      test "reading a profile returns the stored document and what visitors will see" do
        @user.profile.update!(document: <<~HTML)
          <style>body { background: #000 } .orangetext15 { visibility: hidden }</style>
          <marquee><font color="red">hi</font></marquee><script>alert(1)</script>
        HTML

        get api_v1_profile_url, headers: bearer

        assert_response :success
        body = response.parsed_body.fetch("profile")
        # The document is what the author wrote, byte for byte, script and all: it
        # is cleaned on the way out, not on the way in.
        assert_includes body.fetch("document"), "<script>"
        assert_includes body.fetch("html"), "<marquee>"
        refute_includes body.fetch("html"), "script"
        # The stylesheet comes back separately, because it is what lays the page out.
        assert_includes body.fetch("css"), "background: #000"
        assert_includes body.fetch("css"), "visibility: hidden"
        refute_includes body.fetch("html"), "<style"
        assert_equal "vittorio", body.fetch("username")
        assert_equal @user.profile.version, body.fetch("version")
        assert_equal PageCss::MAX_BYTES, body.dig("limits", "css_bytes")
      end

      test "writing a profile replaces the document and echoes what it became" do
        patch api_v1_profile_url,
          params: { profile: { document: %(<style>.main { position: absolute; top: 0 }</style>) +
                                 %(<p>new look</p><iframe src="https://example.com"></iframe>),
                               version: @user.profile.version } },
          headers: bearer, as: :json

        assert_response :success
        body = response.parsed_body.fetch("profile")

        assert_includes body.fetch("document"), "iframe"
        refute_includes body.fetch("html"), "iframe"
        assert_includes body.fetch("html"), "new look"
        # A rule an agent wrote in a style block is reported back with the position
        # it asked for, not silently dropped.
        assert_includes body.fetch("css"), "position: absolute"
        assert_includes @user.profile.reload.document, "new look"
      end

      test "the version an agent writes back is the version it read" do
        get api_v1_profile_url, headers: bearer
        version = response.parsed_body.dig("profile", "version")

        patch api_v1_profile_url,
          params: { profile: { document: "<p>one</p>", version: version } },
          headers: bearer, as: :json

        assert_response :success
        assert_equal version + 1, response.parsed_body.dig("profile", "version")
      end

      test "a write built on a stale read is refused with the current version" do
        stale = @user.profile.version
        @user.profile.update!(document: "<p>written in between</p>")

        patch api_v1_profile_url,
          params: { profile: { document: "<p>my edit</p>", version: stale } },
          headers: bearer, as: :json

        assert_response :conflict
        assert_equal "stale_document", response.parsed_body.dig("error", "code")
        assert_equal stale + 1, response.parsed_body.dig("error", "details", "current_version")
        assert_includes @user.profile.reload.document, "written in between"
      end

      test "a write with no version at all is a blind write and is refused" do
        patch api_v1_profile_url,
          params: { profile: { document: "<p>blind</p>" } },
          headers: bearer, as: :json

        assert_response :bad_request
        assert_equal "missing_parameter", response.parsed_body.dig("error", "code")
        assert_equal "", @user.profile.reload.document
      end

      test "a token is required and is the whole session" do
        get api_v1_profile_url

        assert_response :unauthorized
        assert_equal "invalid_token", response.parsed_body.dig("error", "code")
      end

      test "a token that was never issued, or one that is malformed, is refused" do
        candidates = [ "Bearer rs_#{'0' * 48}", "Bearer nope", "Bearer #{AgentToken.digest(@token.plaintext)}", "Basic #{@token.plaintext}" ]

        candidates.each do |header|
          get api_v1_profile_url, headers: { "Authorization" => header }

          assert_response :unauthorized, "expected #{header.inspect} to be refused"
        end
      end

      test "a token reaches only its own account's profile" do
        other = User.create!(username: "cordelia", email_address: "c@example.com", password: "correct horse battery")
        other.profile.update!(document: "<p>someone else's page</p>")
        @user.profile.update!(document: "<p>mine</p>")

        get api_v1_profile_url, headers: bearer

        assert_includes response.parsed_body.dig("profile", "document"), "mine"
        refute_includes response.parsed_body.dig("profile", "document"), "someone else"
        assert_equal "vittorio", response.parsed_body.dig("profile", "username")
      end

      test "no cookies or CSRF token are needed" do
        patch api_v1_profile_url,
          params: { profile: { document: "<p>x</p>", version: @user.profile.version } },
          headers: bearer, as: :json

        assert_response :success
      end

      test "a write without a document is a bad request" do
        patch api_v1_profile_url, params: { profile: { version: 0 } }, headers: bearer, as: :json

        assert_response :bad_request
        assert_equal "missing_parameter", response.parsed_body.dig("error", "code")
      end

      test "a document over the stored limit is refused with the reason" do
        patch api_v1_profile_url,
          params: { profile: { document: "x" * (Profile::MAX_DOCUMENT_LENGTH + 1), version: @user.profile.version } },
          headers: bearer, as: :json

        assert_response :unprocessable_content
        assert_equal "invalid_profile", response.parsed_body.dig("error", "code")
        assert response.parsed_body.dig("error", "details").present?
      end

      test "an unauthorized request never reaches the profile" do
        get api_v1_profile_url, headers: { "Authorization" => "Bearer rs_#{'1' * 48}" }

        assert_response :unauthorized
        assert_nil response.parsed_body["profile"]
      end

      private
        def bearer
          { "Authorization" => "Bearer #{@token.plaintext}" }
        end
    end
  end
end
