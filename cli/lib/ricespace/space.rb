# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module RiceSpace
  # The client: everything this program knows about the API.
  #
  # Deliberately thin. The server owns the rules — what a page may contain, what a refused
  # request means — and this side's job is to send the right thing, keep a write safe with
  # the revision it was built on, and turn a failure into one sentence a person can act on.
  #
  # It is also the only part that touches a credential, and it never prints one.
  class Space
    # The address this client speaks to. Public because a folder records it.
    attr_reader :base

    def initialize(base, token)
      @base = base.to_s.strip.sub(%r{/+\z}, "")
      @token = token.to_s.strip
    end

    # The account this token belongs to. Also how a token is checked, because it is the
    # smallest request that needs one.
    def whoami
      raw = get("/api/v1/profile")
      username = raw.dig("profile", "username") || raw["username"]

      raise ApiError.new("the space answered without a username") if username.nil?

      { username: username, raw: raw }
    end

    # The page, as the API presents it.
    def page
      raw = get("/api/v1/profile")
      profile = raw["profile"] || raw

      required = %w[username url document html css version]
      missing = required.reject { |key| profile.key?(key) }
      unless missing.empty?
        raise ApiError.new("the space answered without #{missing.join(", ")}")
      end

      profile.merge("raw" => raw)
    end

    # The rice.
    def rice
      raw = get("/api/v1/showcase")
      raw["showcase"] || raw
    end

    # Everything on the page that is not its markup.
    def lists
      get("/api/v1/page")
    end

    # The rating of the page this token speaks for.
    def rating
      raw = get("/api/v1/ratings")
      (raw["rating"] || raw).merge(
        "yours" => raw["yours"],
        "changed" => raw["changed"],
        "raw" => raw
      )
    end

    # This account's opinion of somebody else's page: `like`, `dislike` or `none`.
    #
    # `none` withdraws the opinion, the same act as pressing the button you already pressed.
    #
    # With a `kind` and an `id`, the same opinion is aimed at one posted thing instead: the
    # rice, a shot of it, a build, a demo, a link. That is what an agent has to be able to do
    # — on a page like this the thing being reacted to is the thing that was posted, not the
    # page it sits on, and a client that can only reach the page can only say half of it.
    def rate(username, opinion, kind = nil, id = nil)
      path = if kind.nil?
        "/api/v1/ratings/#{username}"
      else
        "/api/v1/ratings/#{username}/#{kind}/#{id}"
      end

      raw = request(:put, path, { "rating" => opinion })
      (raw["rating"] || raw).merge(
        # `yours` and `changed` describe the request rather than the page, so they sit
        # beside the rating in the response. Reading them from inside the nested object
        # silently yields "no opinion" and "nothing changed" for every answer.
        "yours" => raw["yours"],
        "changed" => raw["changed"],
        "target" => kind ? "#{kind} ##{id}" : "the page",
        "raw" => raw
      )
    end

    # Write the whole document, on top of the revision it was built from. The server
    # refuses a stale write, which is why the version travels with it.
    def push(document, version)
      raw = request(:patch, "/api/v1/profile", {
        "profile" => { "document" => document, "version" => version }
      })
      (raw["profile"] || raw).merge("raw" => raw)
    end

    # Set the named rice facts, leaving every other one alone.
    def set_rice(changes)
      raw = request(:patch, "/api/v1/showcase", { "showcase" => changes })
      (raw["showcase"] || raw).merge("raw" => raw)
    end

    # Replace the named lists, leaving the rest of the page alone.
    def set_lists(changes)
      request(:put, "/api/v1/page", { "page" => changes })
    end

    # The agent contract, as the server serves it to agents.
    def contract
      text(:get, "/agents.md")
    end

    # Upload one picture. A rice shot, a hardware photo, or the account's own picture.
    #
    # Multipart, because that is what an upload is. The account's quota and the file's own
    # ceiling are the server's to enforce — this side sends the bytes and reports what the
    # server said.
    def upload_image(path, kind:, caption: nil, record: nil)
      path = Pathname.new(path)
      raise UsageError, "could not read #{path}: no such file" unless path.file?

      require "net/http"

      uri = URI("#{@base}/api/v1/images")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      request.set_form(
        [
          [ "kind", kind ],
          *(caption ? [ [ "caption", caption ] ] : []),
          *(record ? [ [ "record", record ] ] : []),
          [ "file", path.read, { filename: path.basename.to_s,
                                 content_type: content_type_for(path) } ]
        ],
        "multipart/form-data"
      )

      decode(perform(uri, request))
    end

    # Reorder the rice's shots, whole. One request rather than one per picture, because a
    # folder holds one order.
    def set_shot_order(ids)
      decode(request_raw(:patch, "/api/v1/images/order", { "kind" => "shot", "ids" => ids }.to_json,
        content_type: "application/json"))
    end

    # A picture's bytes, from a URL the space served. Used by `clone` to bring the pictures
    # down into the folder, so the folder holds the page rather than a list of links to it.
    #
    # Redirects are followed, and that is not a nicety: Active Storage answers a picture with
    # a 302 to the file it actually lives at, so a client that stops at the first response
    # gets an empty body and a successful-looking status.
    def fetch_bytes(url, redirects: 5)
      uri = URI(url)

      redirects.times do
        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(Net::HTTP::Get.new(uri))
        end

        case response
        when Net::HTTPSuccess
          return response.body
        when Net::HTTPRedirection
          uri = URI.join(uri.to_s, response["location"])
        else
          raise ApiError.new("#{url} answered #{response.code}")
        end
      end

      raise ApiError.new("#{url} redirected too many times")
    rescue SystemCallError, SocketError => error
      raise ApiError.new("could not fetch #{url}: #{error.message}")
    end

    # A refusal is turned into a sentence. The server's own error body is authoritative
    # when it sent one — it knows why it said no, and it writes for a person — and the
    # status is only a fallback.
    def refusal(status, body)
      parsed = begin
        JSON.parse(body)
      rescue JSON::ParserError
        nil
      end
      error = parsed.is_a?(Hash) ? parsed["error"] : nil
      error = {} unless error.is_a?(Hash)

      fallback = case status.to_i
      when 401 then "the token was refused — is it still issued?"
      when 404 then "the space does not have that endpoint"
      when 409 then "the page moved since you read it; re-read it and reapply your edit"
      else "the space refused the request"
      end

      ApiError.new(
        error["message"] || fallback,
        code: error["code"] || "error",
        status: status
      )
    end

    private

    def get(path) = decode(raw(:get, path))

    def request(method, path, body) = decode(raw(method, path, body))

    def text(method, path)
      perform_uri(method, path, nil)
    end

    def request_raw(method, path, body, content_type:)
      perform_uri(method, path, body, content_type: content_type)
    end

    # One request. The status is data, not an exception: a refusal carries a message
    # written for a person, and it is the message the CLI has to show.
    def raw(method, path, body = nil)
      perform_uri(method, path, body ? JSON.generate(body) : nil,
        content_type: body ? "application/json" : nil)
    end

    def perform_uri(method, path, body, content_type: nil)
      guard_configured!

      uri = URI("#{@base}#{path}")
      klass = {
        get: Net::HTTP::Get, put: Net::HTTP::Put,
        patch: Net::HTTP::Patch, post: Net::HTTP::Post, delete: Net::HTTP::Delete
      }.fetch(method) { raise UsageError, "unsupported method #{method}" }

      request = klass.new(uri)
      request["Authorization"] = "Bearer #{@token}"
      if body
        request["Content-Type"] = content_type || "application/json"
        request.body = body
      end

      perform(uri, request)
    end

    def perform(uri, request)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      body = response.body.to_s
      raise refusal(response.code, body) if response.code.to_i >= 400

      body
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout => error
      raise ApiError.new("could not reach #{@base}: #{error.message}")
    end

    def decode(body)
      JSON.parse(body)
    rescue JSON::ParserError => error
      raise ApiError.new("the space answered with something unreadable: #{error.message}")
    end

    def guard_configured!
      raise UsageError, "no space configured — run `ricespace login`, or pass --url" if @base.empty?
      raise UsageError, "no token configured — run `ricespace login`, or pass --token" if @token.empty?
    end

    def content_type_for(path)
      case path.extname.downcase
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".gif" then "image/gif"
      when ".webp" then "image/webp"
      when ".avif" then "image/avif"
      else "application/octet-stream"
      end
    end
  end
end
