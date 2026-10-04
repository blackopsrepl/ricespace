# frozen_string_literal: true

require "fileutils"
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
    # The signed envelope: written by `folder sign`, checked by `folder verify`.
    # A folder with one is a portable page — the same bytes render the same on
    # any machine, because the hashes say what the files were and the signature
    # says who wrote them.
    ENVELOPE = "manifest.json"

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

    # The folder's own files, hashed. The envelope names exactly what `sign`
    # saw: the page, the rice, every list present, and every asset by content.
    # `ricespace.toml` and the sidecar are the folder's bookkeeping, not the
    # page, so they are not in it — and neither is the envelope itself.
    def digest
      files = {}
      files[PAGE] = P2p::Canonical.file_digest(root.join(PAGE))

      rice_file = root.join(RICE)
      files[RICE] = P2p::Canonical.file_digest(rice_file) if rice_file.file?

      LISTS.each do |_key, filename|
        file = root.join(filename)
        files[filename] = P2p::Canonical.file_digest(file) if file.file?
      end

      assets.each do |path|
        files["#{ASSETS}/#{File.basename(path.to_s)}"] = P2p::Canonical.file_digest(path)
      end

      files
    end

    # Seal the folder: hash its files and sign a `page` record into the local
    # feed. The files stay where they are; the signature lives in the feed, and
    # a copy rides in `manifest.json` so the folder carries its own proof.
    def sign(feed:, private_hex:, device_public:)
      record = P2p::Record.build(
        author: feed.author, signer: device_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "page", body: { "document" => page, "files" => digest },
        sign_with: private_hex
      )
      feed.append(record)
      root.join(ENVELOPE).write(JSON.pretty_generate(signed_envelope(record)) + "\n")
      record
    end

    # Seal everything, for replicating peers: the page plus the rice, the
    # lists and the asset manifest as their own records, so a node holding the
    # feed can render the page without the folder's files. Bodies are
    # self-contained — facts and entries inline, pictures by content hash with
    # bytes fetched separately. Returns all appended records, page first.
    def sign_all(feed:, private_hex:, device_public:)
      bodies = subscribing_bodies
      records = bodies.map do |kind, body|
        record = P2p::Record.build(
          author: feed.author, signer: device_public,
          seq: feed.next_seq, prev: feed.prev_hash,
          kind: kind, body: body, sign_with: private_hex
        )
        feed.append(record)
        record
      end
      envelope = records.first.merge(
        "records" => records.to_h { |record| [ record["kind"], P2p::Record.hash_of(record) ] }
      )
      root.join(ENVELOPE).write(JSON.pretty_generate(envelope) + "\n")
      records
    end

    # The bodies a remote node renders from: page (the document + file hashes),
    # rice (facts inline + shots as content hashes), lists (entries inline,
    # friends as peer keys), assets (pictures as content hashes).
    def subscribing_bodies
      bodies = [
        [ "page", { "document" => page, "files" => digest } ],
        [ "rice", rice_body ],
        [ "lists", lists_body ]
      ]
      asset_entries = asset_manifest
      bodies << [ "assets", { "files" => asset_entries } ] unless asset_entries.empty?
      bodies
    end

    def rice_body
      facts = rice.is_a?(Hash) ? rice : {}
      shots = Array(facts["shots"]).filter_map do |shot|
        next unless shot.is_a?(Hash)

        url = shot["url"].to_s
        name = self.class.asset_name(url)
        file = name ? root.join(ASSETS, name) : nil
        entry = { "caption" => shot["caption"].to_s }
        entry["sha256"] = P2p::Canonical.file_digest(file) if file&.file?
        entry
      end
      {
        "title" => facts["title"].to_s, "summary" => facts["summary"].to_s,
        "details" => facts["details"].to_s,
        "facts" => facts.reject { |key, _| %w[title summary details shots].include?(key.to_s) },
        "shots" => shots
      }
    end

    def lists_body
      lists.each_with_object({}) do |(key, value), acc|
        acc[key.to_s] = Array(value).map do |entry|
          entry.is_a?(Hash) ? comparable_entry(entry) : entry
        end
      end
    end

    def asset_manifest
      assets.filter_map do |path|
        name = File.basename(path.to_s)
        { "name" => name, "sha256" => P2p::Canonical.file_digest(path),
          "kind" => "shot", "bytes" => path.size }
      end
    end

    # The editable fields of a list entry: derived keys (urls, ids, ordering)
    # stay with the site that derived them.
    def comparable_entry(entry)
      entry.reject { |field, _| DERIVED.include?(field.to_s) }
    end

    # What the folder claims about itself: its envelope, or nothing.
    def signed_envelope(record = nil)
      record ||= begin
        file = root.join(ENVELOPE)
        return nil unless file.file?

        JSON.parse(file.read)
      rescue JSON::ParserError
        raise UsageError, "#{ENVELOPE} is not JSON"
      end

      record.is_a?(Hash) ? record.transform_keys(&:to_s) : nil
    end

    # Check the folder against its envelope: every named file still hashes the
    # same, and the signature verifies. Returns the record on success.
    # A `sign_all` envelope carries `records` beside the page record — the extra
    # key is the manifest of the other sealed records, not part of the record.
    def verify!
      envelope = signed_envelope
      raise UsageError, "no #{ENVELOPE} here — sign the folder first" if envelope.nil?

      record = P2p::Record.from_hash(envelope.reject { |key, _| key == "records" })
      raise UsageError, "the envelope is not a page record" unless record["kind"] == "page"

      unless P2p::Record.signature_valid?(record)
        raise UsageError, "the signature does not verify — this folder is not who it claims"
      end

      expected = record.dig("body", "files") || {}
      actual = digest
      missing = expected.keys - actual.keys
      changed = expected.keys.select { |name| actual.key?(name) && actual[name] != expected[name] }
      unless missing.empty? && changed.empty?
        details = (missing.map { |name| "missing #{name}" } + changed.map { |name| "#{name} changed" })
        raise UsageError, "the folder changed since it was signed: #{details.join(", ")}"
      end

      record
    end

    # A static copy of the folder any dumb HTTP server can host: the page, its
    # lists, its assets, and the envelope that proves them. This is the
    # sneakernet transport — a USB stick that carries a page.
    def export_to(target)
      target = Pathname.new(target.to_s)
      target.mkpath

      names = [ PAGE, RICE, ENVELOPE ] + LISTS.values
      names.each do |name|
        file = root.join(name)
        FileUtils.cp(file, target.join(name)) if file.file?
      end

      from = root.join(ASSETS)
      if from.directory?
        to = target.join(ASSETS)
        to.mkpath
        from.children.select(&:file?).each { |child| FileUtils.cp(child, to.join(child.basename)) }
      end

      target
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
