# frozen_string_literal: true

require "json"
require "pathname"

module RiceSpace
  # A folder that is your space.
  #
  # `clone` writes your page out as files, `push` sends the folder back, `preview` draws it
  # locally. The reason to have this at all is that a page is a document written by a person,
  # and a person writes documents in an editor on their own machine — not in a textarea, and
  # not one resource at a time from a shell.
  #
  # The shape of the folder is the API's own shape written down: `page.html` is the markup,
  # and one JSON file per list holds what the API holds. That is deliberate — a folder in a
  # second format would be a second thing to keep in step with the API, and the API already
  # has a shape.
  #
  # What is *not* in the folder is the token. A folder is a thing a person puts in git, and
  # `ricespace.toml` carries the address only; the token stays in the config file.
  class Folder
    MANIFEST = "ricespace.toml"
    PAGE = "page.html"
    RICE = "rice.json"

    # The lists, in the API's own shape. Each is one file, because each is one list.
    LISTS = {
      "blurbs" => "blurbs.json",
      "demos" => "demos.json",
      "builds" => "builds.json",
      "links" => "links.json",
      "friends" => "friends.json"
    }.freeze

    # The name the command uses, which is not always the API's field name: the command is
    # `hardware`, the field is `builds`.
    COMMAND_FOR = { "hardware" => "builds" }.freeze

    ASSETS = "assets"

    # What is in a folder, described for a person — the diff a push shows before it sends.
    Changes = Struct.new(:summary, :assets) do
      def empty? = summary.empty? && !assets
    end

    attr_reader :root, :page, :page_version, :rice, :lists, :assets

    def initialize(root:, page:, page_version:, rice:, lists:, assets:)
      @root = root
      @page = page
      @page_version = page_version
      @rice = rice
      @lists = lists
      @assets = assets
    end

    # Read a folder. A folder with no `page.html` is not a folder — that is the one file that
    # makes it one, and everything else is optional.
    def self.read(dir)
      root = Pathname.new(dir.to_s)
      page_file = root.join(PAGE)

      unless page_file.file?
        raise UsageError,
          "#{root} is not a space folder — no #{PAGE} in it (make one with `ricespace folder clone`)"
      end

      page = page_file.read

      rice = read_json_object(root.join(RICE))

      lists = LISTS.each_with_object({}) do |(key, filename), acc|
        value = read_json(root.join(filename))
        acc[key] = value unless value.nil?
      end

      assets = begin
        dir = root.join(ASSETS)
        dir.directory? ? dir.children.select(&:file?).sort : []
      rescue SystemCallError
        []
      end

      new(root: root, page: page, page_version: read_sidecar(page_file), rice: rice,
        lists: lists, assets: assets)
    end

    # Write a space out as a folder.
    def self.write_out(target, space)
      target = Pathname.new(target.to_s)
      target.mkpath

      wrote = []

      page = space.page
      target.join(PAGE).write(page["document"].to_s)
      wrote << "#{PAGE} (revision #{page["version"]})"
      target.join("#{PAGE}.ricespace").write(
        JSON.generate({ "version" => page["version"], "username" => page["username"] })
      )

      rice = space.rice
      target.join(RICE).write(JSON.pretty_generate(rice) + "\n")
      wrote << RICE

      lists = space.lists["page"] || {}
      LISTS.each do |key, filename|
        value = lists[key]
        next if value.nil?

        target.join(filename).write(JSON.pretty_generate(value) + "\n")
        wrote << filename
      end

      # The address and nothing secret. A folder is a thing a person puts in git, and the
      # token is not part of the page.
      target.join(MANIFEST).write(<<~TOML)
        # This folder is a RiceSpace page.
        #
        # The address is here; the token deliberately is not — it stays in
        # ~/.config/ricespace/config.json, which is not in a repository.
        address = "#{space.base}"
      TOML
      wrote << MANIFEST

      # The pictures, so the folder holds the page rather than a list of links to it.
      wrote.concat(fetch_assets(target, space, rice))

      wrote
    end

    # Bring down every picture the rice and the hardware point at.
    def self.fetch_assets(target, space, rice)
      wrote = []
      assets = target.join(ASSETS)

      urls = Array(rice["shots"]).filter_map { |shot| shot["url"] }

      urls.each do |url|
        name = asset_name(url)
        next if name.nil?

        file = assets.join(name)
        next if file.exist?

        begin
          bytes = space.fetch_bytes(url)
        rescue ApiError
          next
        end

        assets.mkpath
        file.binwrite(bytes)
        wrote << "#{ASSETS}/#{name} (#{bytes.bytesize} bytes)"
      end

      wrote
    end

    # The name an asset file is given, from a URL the site serves it at. The last segment of
    # the URL is the only stable part of it, and it is what a person would recognise.
    def self.asset_name(url)
      last = url.to_s.sub(%r{/+\z}, "").split("/").last.to_s
      cleaned = last.split("?").first.to_s
      return nil if cleaned.empty? || cleaned.include?("..")

      cleaned
    end

    # What the folder would change, against what the space has now. Read-only.
    def changes(space)
      summary = []
      assets = false

      live = space.page
      if live["document"].to_s != page
        summary << "#{PAGE}: #{page.lines.size} lines now"
      end

      live_rice = space.rice
      rice.each do |key, value|
        next if live_rice[key] == value

        summary << "#{RICE}: #{key} → #{value.to_s[0, 40]}"
      end

      live_lists = space.lists["page"] || {}
      lists.each do |key, value|
        # Compared on what a person edits. The API returns derived keys (a picture's url,
        # who a friend is) that a folder never holds, and comparing those would report every
        # list as changed forever.
        next if comparable(key, live_lists[key]) == comparable(key, value)

        summary << "#{LISTS[key] || key}: #{Array(value).size} entries"
      end

      assets = !new_assets(space).empty?

      Changes.new(summary, assets)
    end

    # Send the folder. Everything, in one transaction on the server: the page, the rice and
    # every list, so a folder is never half-applied.
    def push(space, force: false)
      done = []

      current = space.page
      # The sidecar is the revision this folder was built on, and a write on a stale one is
      # refused by the server. `--force` means "send it anyway", so it builds on the revision
      # that is current now — the sidecar is by definition a stale opinion on that path.
      unless force || page_version.nil? || page_version == current["version"]
        raise ApiError.new(
          "the page moved since this folder was cloned (it is at revision #{current["version"]}, " \
          "this folder was built on #{page_version}) — clone again, or pass --force"
        )
      end

      if force || page != current["document"].to_s
        version = force ? current["version"] : (page_version || current["version"])
        saved = space.push(page, version)
        done << "#{PAGE} → revision #{saved["version"]}"
      end

      done.concat(push_rice(space))
      done.concat(push_lists(space))
      done.concat(push_assets(space))

      write_sidecar(space.page) unless done.empty?

      done
    end

    # Stage the folder where the running site can read it, so the site's own renderer can
    # draw it. This is what makes `preview` honest: the CLI does not reimplement the rules.
    def stage_for_preview(preview_root, name)
      target = Pathname.new(preview_root.to_s).join(name)
      target.mkpath

      target.join(PAGE).write(page)
      target.join(RICE).write(JSON.generate(rice)) unless rice.empty?

      lists.each do |key, value|
        target.join(LISTS[key] || "#{key}.json").write(JSON.generate(value))
      end

      target
    end

    private

    def push_rice(space)
      return [] if rice.empty?

      live = space.rice
      edits = rice.reject { |key, value| live[key] == value }
      return [] if edits.empty?

      space.set_rice(edits)
      [ "#{RICE}: #{edits.keys.join(", ")}" ]
    end

    def push_lists(space)
      live = space.lists["page"] || {}
      edits = lists.reject { |key, value| comparable(key, live[key]) == comparable(key, value) }
      return [] if edits.empty?

      space.set_lists(edits)
      edits.map { |key, value| "#{LISTS[key] || key}: #{Array(value).size} entries" }
    end

    def push_assets(space)
      uploads = new_assets(space)
      return [] if uploads.empty?

      uploads.map do |path|
        space.upload_image(path, kind: "shot", caption: nil)
        "#{ASSETS}/#{File.basename(path)}"
      end
    end

    # The files in `assets/` the space does not have yet, by name.
    def new_assets(space)
      rice_urls = Array(space.rice["shots"]).filter_map { |shot| shot["url"].to_s }
      have = rice_urls.map { |url| Folder.asset_name(url) }.compact

      assets.reject { |path| have.include?(File.basename(path.to_s)) }
    end

    # The part of a record a folder owns: the fields a person edits, ignoring the ones the
    # server derives (urls, ids, platform labels, ordering bookkeeping).
    DERIVED = %w[url id position shot_order photos embeds platform platform_label owner].freeze

    def comparable(key, value)
      Array(value).map do |entry|
        next entry unless entry.is_a?(Hash)

        entry.reject { |field, _| DERIVED.include?(field) }
      end
    end

    def write_sidecar(page)
      root.join("#{PAGE}.ricespace").write(
        JSON.generate({ "version" => page["version"], "username" => page["username"] })
      )
    end

    def self.read_json(path)
      path = Pathname.new(path.to_s)
      return nil unless path.file?

      JSON.parse(path.read)
    rescue JSON::ParserError => error
      raise UsageError, "#{path} is not JSON: #{error.message}"
    end

    def self.read_json_object(path)
      value = read_json(path)
      value.is_a?(Hash) ? value : {}
    end

    # The revision `page.html` was read at, from the sidecar. Nil when the folder was written
    # by hand rather than cloned.
    def self.read_sidecar(page_file)
      path = Pathname.new("#{page_file}.ricespace")
      return nil unless path.file?

      JSON.parse(path.read)["version"]
    rescue JSON::ParserError, NoMethodError
      nil
    end
  end
end
