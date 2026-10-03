# frozen_string_literal: true

require "json"
require "optparse"
require "pathname"

module RiceSpace
  # The surface: the commands, their flags, and the words a person types.
  #
  # Written by hand rather than with a framework, because the flags are the design here and
  # the design is small. What it decides nothing about is the API — that is Space's — and how
  # anything is printed, which is Ui's.
  class Command
    PAGE_COMMANDS = %w[show pull push rice links demos hardware blurbs friends].freeze
    RATE_COMMANDS = %w[show set].freeze
    FOLDER_COMMANDS = %w[clone push preview watch].freeze

    # The one sentence a person is given when they type something the CLI cannot do.
    HELP = <<~TEXT
      ricespace talks to your space over the same HTTP API an agent uses, with the same
      token. Everything it can do, you can do from the studio in a browser — this is for
      the terminal you already live in.

      Usage: ricespace [options] <command> [args]

      Commands
        login                      Save the space's address and your token
        whoami                     Show the address and token this machine will use
        ping                       Check the space is reachable and the token accepted
        contract                   What the API can do to your page, as agents get it
        completions <shell>        Shell completions (bash, zsh, fish)
        page show                  Your page: the rice, the markup, the facts
        page pull [file]           Read your markup into a file ("-" for stdout)
        page push <file>           Write a file in as your markup
        page rice [flags]          Show the rice, or set its facts
        page links|demos|hardware|blurbs [--set FILE|--clear]
        page friends [usernames…]  Show or set your friends list (--clear to empty)
        rate show                  What people think of your page
        rate set <user> <opinion>  like, dislike, or none
        folder clone [dir]         Write your space out as a folder of files
        folder push [dir]          Send the folder to your space
        folder preview [dir]       Draw the folder locally, with the site's renderer
        folder watch [dir]         Push on every save

      Options
        -H, --url URL              Where the space is (env RICESPACE_URL)
        -t, --token TOKEN          Your agent token (env RICESPACE_TOKEN)
            --json                 Print raw API responses instead of the rendered view
            --no-colour            Plain output, even on a terminal
        -q, --quiet                Suppress the banner
        -h, --help                 This
        -v, --version              The version
    TEXT

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
      @options = { json: false }
    end

    def run
      command = extract_global_options!

      case command
      when nil, "help", "--help", "-h" then puts HELP
      when "--version", "-v" then puts "ricespace #{VERSION}"
      else dispatch(command)
      end
    rescue Error => error
      Ui.failure(error)
      exit 1
    end

    private

    # Pull the global flags off the front, wherever they appear, so `ricespace page show
    # --json` and `ricespace --json page show` both mean the same thing.
    def extract_global_options!
      rest = []
      @argv.each_with_index do |arg, index|
        case arg
        when "--json" then @options[:json] = true
        when "--no-colour" then Ui.styled = false
        when "-q", "--quiet" then ENV["RICESPACE_QUIET"] = "1"
        when "-H", "--url"
          @options[:url] = @argv[index + 1]
          @skip = index + 1
        when "-t", "--token"
          @options[:token] = @argv[index + 1]
          @skip = index + 1
        else
          rest << arg unless index == @skip
        end
      end
      # A flag given as `--url=…` arrives as one word.
      @argv = rest.reject { |a| a.start_with?("--url=", "--token=") }
      @argv.each do |arg|
        @options[:url] ||= arg.split("=", 2).last if arg.start_with?("--url=")
        @options[:token] ||= arg.split("=", 2).last if arg.start_with?("--token=")
      end
      @options[:url] ||= ENV["RICESPACE_URL"]
      @options[:token] ||= ENV["RICESPACE_TOKEN"]
      @argv.shift
    end

    def dispatch(command)
      case command
      when "login" then login
      when "whoami" then whoami
      when "ping" then ping
      when "contract" then contract
      when "completions" then completions
      when "page" then page_command
      when "rate" then rate_command
      when "folder" then folder_command
      else
        raise UsageError, "unknown command #{command.inspect} — run `ricespace help`"
      end
    end

    # ---- the connection ---------------------------------------------------------------

    def login
      url = option("-H", "--url") || @options[:url]
      token = option("-t", "--token") || @options[:token]

      if url.to_s.strip.empty? || token.to_s.strip.empty?
        raise UsageError,
          "login needs both a space and a token:\n" \
          "`ricespace login --url https://rice.example.com --token rs_…`"
      end

      # Checked before it is saved: a stored token that does not work is worse than none,
      # because the next command fails somewhere less obvious.
      who = Space.new(url, token).whoami

      file = Config.save(url: url, token: token)

      Ui.wordmark
      Ui.ok("Saved.")
      Ui.key_value("speaking for", "@#{who[:username]}")
      Ui.key_value("space", url)
      Ui.key_value("config", file.to_s)
    end

    def whoami
      base, token = credentials

      if base.empty?
        Ui.wordmark
        Ui.key_value("space", "(not set)")
        Ui.key_value("token", token.empty? ? "(not set)" : "set")
        Ui.notice("Nothing to call yet — run `ricespace login`.")
        return
      end

      who = Space.new(base, token).whoami

      Ui.wordmark
      Ui.key_value("space", base)
      Ui.key_value("username", "@#{who[:username]}")
      Ui.key_value("token", mask(token))
      Ui.key_value("config", Config.path.to_s)
    end

    def ping
      base, token = credentials
      who = Space.new(base, token).whoami

      Ui.wordmark
      Ui.ok("#{base} is reachable and the token works.")
      Ui.key_value("speaking for", "@#{who[:username]}")
      Ui.key_value("latency", "#{@options[:latency]}ms") if @options[:latency]
    end

    def contract
      base, token = credentials
      print Space.new(base, token).contract
    end

    def completions
      shell = @argv.shift
      raise UsageError, "say which shell: bash, zsh or fish" if shell.nil?

      print Completions.for(shell)
    end

    # ---- page ---------------------------------------------------------------------------

    def page_command
      sub = @argv.shift
      raise UsageError, "page needs one of: #{PAGE_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "show" then page_show
      when "pull" then page_pull
      when "push" then page_push
      when "rice" then page_rice
      when "links", "demos", "hardware", "blurbs" then page_list(Folder::COMMAND_FOR[sub] || sub)
      when "friends" then page_friends
      else
        raise UsageError, "unknown page command #{sub.inspect} — one of: #{PAGE_COMMANDS.join(", ")}"
      end
    end

    def page_show
      space = client
      page = space.page
      rice = begin
        space.rice
      rescue ApiError
        nil
      end

      return Ui.raw(page["raw"]) if @options[:json]

      Ui.wordmark
      Ui.key_value("page", "@#{page["username"]}")
      Ui.key_value("at", page["url"])

      Ui.section("the rice")
      if rice && !(rice["title"].to_s + rice["summary"].to_s).empty?
        Ui.rice_mark
        Ui.key_value("title", rice["title"]) if rice["title"]
        Ui.key_value("summary", rice["summary"]) if rice["summary"]
        Array(rice["filled"]).each { |fact| Ui.key_value(fact["label"], fact["value"]) }
        Array(rice["shots"]).each_with_index do |shot, i|
          Ui.key_value("shot #{i + 1}", "#{shot["caption"]} (#{human_bytes(shot["bytes"])})")
        end
      else
        puts "  #{Ui.send(:dim, "no rice yet — set one with `ricespace page rice --title …`")}"
      end

      Ui.section("the page")
      Ui.key_value("revision", page["version"])
      Ui.key_value("changed", page["updated_at"])
      Ui.key_value("markup", "#{page["document"].to_s.bytesize} bytes")
      Ui.key_value("renders to", "#{page["html"].to_s.bytesize} markup · #{page["css"].to_s.bytesize} stylesheet")
      if page["limits"]
        Ui.key_value("limits", "#{page["limits"]["document_bytes"]} / #{page["limits"]["html_bytes"]} / #{page["limits"]["css_bytes"]} bytes")
      end
    end

    def page_pull
      file = @argv.shift || "-"
      page = client.page

      if file == "-"
        print page["document"]
        $stderr.puts "ricespace: revision #{page["version"]}" if ENV["RICESPACE_VERBOSE"]
        return
      end

      Pathname.new(file).write(page["document"])
      # The revision is written beside the file, because it is what makes the next push safe,
      # and there is nowhere else to keep it.
      sidecar = "#{file}.ricespace"
      Pathname.new(sidecar).write(
        JSON.generate({ "version" => page["version"], "username" => page["username"] })
      )

      Ui.notice("Read revision #{page["version"]} into #{file}.")
      Ui.key_value("beside it", sidecar)
    end

    def page_push
      file = @argv.shift
      raise UsageError, "push needs a file, or `-` to read standard input" if file.nil?

      force = @argv.delete("--force")
      document = read_document(file)
      space = client

      # The revision this edit is built on, from the sidecar `pull` left behind.
      known = read_sidecar_version(file)

      # `--force` means "send it anyway", so it reads the revision that is current now — the
      # sidecar is a stale opinion by definition on that path. Without it, the sidecar is what
      # makes the write safe, and its absence is refused rather than guessed at.
      version = if force
        space.page["version"]
      elsif known
        known
      else
        raise UsageError,
          "no revision beside the file — pull it first, or pass --force to send it anyway"
      end

      page = space.push(document, version)

      return Ui.raw(page["raw"]) if @options[:json]

      Ui.notice("Saved. The page is now revision #{page["version"]}.")
      Ui.key_value("url", page["url"])
    end

    def page_rice
      space = client

      facts = {
        "title" => option("--title"), "summary" => option("--summary"),
        "hardware" => option("--hardware"), "window_manager" => option("--wm"),
        "bar" => option("--bar"), "terminal" => option("--terminal"),
        "font" => option("--font"), "theme" => option("--theme")
      }.compact

      # No flags: show the rice rather than quietly doing nothing.
      if facts.empty?
        rice = space.rice
        return Ui.raw(rice) if @options[:json]

        Ui.wordmark
        Ui.section("the rice")
        Ui.rice_mark
        Ui.key_value("title", rice["title"]) if rice["title"]
        Ui.key_value("summary", rice["summary"]) if rice["summary"]
        Array(rice["filled"]).each { |fact| Ui.key_value(fact["label"], fact["value"]) }
        return
      end

      rice = space.set_rice(facts)
      return Ui.raw(rice["raw"]) if @options[:json]

      Ui.notice("Rice saved.")
      Ui.section("the rice")
      Array(rice["filled"]).each { |fact| Ui.key_value(fact["label"], fact["value"]) }
      Ui.key_value("title", rice["title"]) if rice["title"]
      Ui.key_value("summary", rice["summary"]) if rice["summary"]
    end

    def page_list(kind)
      space = client
      set = option("--set")
      clear = @argv.delete("--clear")

      # Nothing to change: show the list.
      if set.nil? && !clear
        value = (space.lists["page"] || {})[kind] || []
        return Ui.raw(value) if @options[:json]

        Ui.wordmark
        Ui.list(kind, value)
        return
      end

      value = if clear
        []
      else
        parsed = JSON.parse(read_document(set || "-")) rescue nil
        if parsed.nil?
          raise UsageError, "#{set || "standard input"} is not JSON"
        end
        # A file may hold the bare array or the object `--json` printed; both are accepted,
        # so `ricespace page links --json > links.json` round-trips.
        parsed.dig("page", kind) || parsed[kind] || parsed
      end

      unless value.is_a?(Array)
        raise UsageError, "#{kind} must be a JSON array, got #{value.class.name.downcase}"
      end

      space.set_lists(kind => value)

      return Ui.raw(value) if @options[:json]

      Ui.notice("Saved.")
      Ui.list(kind, value)
    end

    def page_friends
      space = client
      clear = @argv.delete("--clear")
      usernames = @argv.reject { |a| a.start_with?("--") }

      if usernames.empty? && !clear
        value = (space.lists["page"] || {})["friends"] || []
        return Ui.raw(value) if @options[:json]

        Ui.wordmark
        Ui.list("friends", value)
        return
      end

      entries = clear ? [] : usernames.map { |name| { "username" => name } }
      space.set_lists("friends" => entries)

      return Ui.raw(entries) if @options[:json]

      Ui.notice("Saved.")
      Ui.list("friends", entries)
    end

    # ---- rate ---------------------------------------------------------------------------

    def rate_command
      sub = @argv.shift
      raise UsageError, "rate needs one of: #{RATE_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "show" then rate_show
      when "set" then rate_set
      else
        raise UsageError, "unknown rate command #{sub.inspect} — one of: #{RATE_COMMANDS.join(", ")}"
      end
    end

    def rate_show
      rating = client.rating
      return Ui.raw(rating["raw"]) if @options[:json]

      Ui.wordmark
      Ui.section("rating")
      Ui.key_value("page", "@#{rating["username"]}")
      Ui.key_value("at", rating["url"])
      Ui.key_value("score", rating["score"])
      Ui.key_value("likes", rating["likes"])
      Ui.key_value("dislikes", rating["dislikes"])
      Ui.key_value("raters", rating["raters"])
    end

    def rate_set
      username = @argv.shift
      opinion = @argv.shift.to_s.downcase

      raise UsageError, "rate set needs a username and an opinion" if username.nil?

      unless %w[like dislike none].include?(opinion)
        raise UsageError, "say like, dislike or none — `none` takes your rating back"
      end

      rating = client.rate(username, opinion)
      return Ui.raw(rating["raw"]) if @options[:json]

      Ui.wordmark
      Ui.section("rating")
      Ui.key_value("you said", rating["yours"] || "nothing")
      Ui.key_value("changed", rating["changed"] ? "yes" : "no, that was already your opinion")
      Ui.key_value("page", "@#{rating["username"]}")
      Ui.key_value("score", rating["score"])
      Ui.key_value("likes", rating["likes"])
      Ui.key_value("dislikes", rating["dislikes"])
    end

    # ---- folder -------------------------------------------------------------------------

    def folder_command
      sub = @argv.shift
      raise UsageError, "folder needs one of: #{FOLDER_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "clone" then folder_clone
      when "push" then folder_push
      when "preview" then folder_preview
      when "watch" then folder_watch
      else
        raise UsageError, "unknown folder command #{sub.inspect} — one of: #{FOLDER_COMMANDS.join(", ")}"
      end
    end

    def folder_clone
      dir = @argv.reject { |a| a.start_with?("--") }.first || "."
      force = @argv.include?("--force")
      target = Pathname.new(dir)

      # An existing folder is only written into when the person said so: `clone .` in a
      # directory that already has a `page.html` would quietly replace it.
      if target.join(Folder::PAGE).exist? && !force
        raise UsageError, "#{target} already has a #{Folder::PAGE} — pass --force to replace it"
      end

      wrote = Folder.write_out(target, client)

      Ui.wordmark
      Ui.notice("Cloned into #{target}.")
      wrote.each { |name| Ui.key_value("wrote", name) }
      Ui.key_value("next", "edit the files, then `ricespace folder preview`")
    end

    def folder_push
      dir = @argv.reject { |a| a.start_with?("--") }.first || "."
      dry_run = @argv.include?("--dry-run")
      force = @argv.include?("--force")

      space = client
      folder = Folder.read(dir)
      changes = folder.changes(space)

      if changes.empty?
        Ui.ok("Nothing has changed since the last clone or push.")
        return
      end

      Ui.notice("This folder would change:")
      changes.summary.each { |line| Ui.key_value("·", line) }
      Ui.key_value("·", "#{folder.assets.size} picture(s) in assets/") if changes.assets

      if dry_run
        Ui.key_value("note", "--dry-run: nothing was sent")
        return
      end

      folder.push(space, force: force).each { |line| Ui.ok(line) }
    end

    def folder_preview
      dir = @argv.reject { |a| a.start_with?("--") || a.start_with?("--port") }.first || "."
      stage_only = @argv.include?("--stage-only")

      folder = Folder.read(dir)

      # The preview is drawn by the site, not by this program: the rules it must show are the
      # site's rules, and the way to be sure of that is to use them. So the folder is staged
      # where the running site can read it, and the person is pointed at the address that
      # renders it.
      app_root = preview_root
      name = preview_name(folder, dir)
      staged = folder.stage_for_preview(app_root, name)

      Ui.key_value("staged", staged.to_s)
      return if stage_only

      site = option("--renderer") || Config.load["url"] || ENV["RICESPACE_URL"] || "http://127.0.0.1:3000"
      url = "#{site.sub(%r{/+\z}, "")}/preview/#{name}"

      Ui.notice("Preview ready:")
      Ui.key_value("open", url)
      Ui.key_value("note", "drawn by #{site} with the site's own cleaner — what survives there survives here")

      unless reaches?(url)
        Ui.warn("#{site} is not answering — start it with `make serve`")
      end
    end

    def folder_watch
      dir = @argv.reject { |a| a.start_with?("--") || a.start_with?("--every") }.first || "."
      every = (option("--every") || 2).to_i

      space = client
      path = Pathname.new(dir)

      Ui.notice("Watching #{path} — Ctrl-C to stop.")
      Ui.key_value("every", "#{every}s")
      Ui.key_value("what", "push on change, so saving a file puts it on your page")

      # A cheap change signal: the size and modification time of every file, summed. Content
      # hashing would be more precise and slower; a stamp is enough to notice a save.
      stamp = folder_stamp(path)

      loop do
        sleep every

        now = folder_stamp(path)
        next if now == stamp
        stamp = now

        begin
          folder = Folder.read(path)
          folder.stage_for_preview(preview_root, preview_name(folder, dir))
          folder.push(space, force: false).each { |line| Ui.ok(line) }
        rescue Error => error
          Ui.failure(error)
        end
      end
    end

    # ---- plumbing -----------------------------------------------------------------------

    def client
      base, token = credentials
      Space.new(base, token)
    end

    # A flag beats the environment, which beats the file. A one-off run against another space
    # does not have to rewrite what is saved here.
    def credentials
      saved = Config.load
      base = @options[:url] || saved["url"] || ""
      token = @options[:token] || saved["token"] || ""

      [ base, token ]
    end

    def option(short, long = nil)
      index = @argv.index(short) || (long && @argv.index(long))
      return nil if index.nil?

      value = @argv[index + 1]
      @argv.delete_at(index)
      @argv.delete_at(index)
      value
    end

    def read_document(file)
      return $stdin.read if file == "-"

      path = Pathname.new(file)
      raise UsageError, "could not read #{file}: no such file" unless path.file?

      path.read
    end

    def read_sidecar_version(file)
      path = Pathname.new("#{file}.ricespace")
      return nil unless path.file?

      JSON.parse(path.read)["version"]
    rescue JSON::ParserError
      nil
    end

    # Where the site keeps the folders it has been asked to preview.
    #
    # The preview is drawn by the app, so the folder has to be somewhere the app can read.
    # The app's own `tmp/preview` is that place, named by the same variable the server uses
    # for its root, so a CLI run beside a checkout and a CLI pointed at a deployed app agree.
    def preview_root
      return Pathname.new(ENV["RICESPACE_APP_ROOT"]).join("tmp", "preview") if ENV["RICESPACE_APP_ROOT"]

      # Walk up from the working directory looking for the app, which is where a person is
      # standing when they are editing a page next to a checkout.
      here = Pathname.new(Dir.pwd)
      loop do
        return here.join("tmp", "preview") if here.join("config", "routes.rb").file?
        break if here.root? || here.parent == here
        here = here.parent
      end

      raise UsageError,
        "could not find the ricespace app — run this from beside a checkout, or set RICESPACE_APP_ROOT"
    end

    # The name a staged folder is served under. Derived from the folder itself so `preview`
    # and `watch` in the same folder agree, and reduced to characters a URL can carry.
    def preview_name(folder, dir)
      raw = if dir == "." || folder.root.to_s.empty?
        File.basename(Dir.pwd)
      else
        folder.root.basename.to_s
      end

      cleaned = raw.gsub(/[^A-Za-z0-9_-]/, "-")
      cleaned.empty? ? "space" : cleaned
    end

    # A cheap change signal for a folder. The `.ricespace` sidecars are skipped, and that is
    # not an optimisation: a push writes one, so counting them would make every push look
    # like the change it just made, and `watch` would push in a loop of its own making.
    def folder_stamp(path)
      return 0 unless path.directory?

      path.children.reject { |c| c.to_s.end_with?(".ricespace") }.filter_map { |child|
        next unless child.file?

        stat = child.stat
        stat.size + stat.mtime.to_f
      }.sum
    rescue SystemCallError
      0
    end

    # Whether an address answers at all. Used only to warn: a preview that will not render is
    # still worth staging, because the person may be about to start the site.
    def reaches?(url)
      uri = URI(url)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: 1, read_timeout: 2) { |http| http.request(Net::HTTP::Head.new(uri)) }
      true
    rescue StandardError
      false
    end

    def mask(token)
      trimmed = token.to_s.strip
      return "(not set)" if trimmed.empty?
      return "rs_…" if trimmed.length <= 12

      "#{trimmed[0, 7]}…#{trimmed[-4, 4]}"
    end

    def human_bytes(bytes)
      return "nothing" if bytes.nil?

      bytes = bytes.to_i
      return "#{bytes} bytes" if bytes < 1024

      "#{(bytes / 1024.0).round} KB"
    end
  end
end
