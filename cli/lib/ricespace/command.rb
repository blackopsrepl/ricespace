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
    FOLDER_COMMANDS = %w[clone push preview watch sign verify export goodbye prune].freeze
    IDENTITY_COMMANDS = %w[create join show backup device-add device-revoke rotate recover endorse prove].freeze
    PEER_COMMANDS = %w[serve address add list remove sync keygen bootstrap status].freeze
    NET_COMMANDS = %w[up down wait].freeze

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
        rate set <user> <opinion> [kind/id]
                                   like, dislike, or none — on their page,
                                   or on one thing they posted
        folder clone [dir]         Write your space out as a folder of files
        folder push [dir]          Send the folder to your space
        folder preview [dir]       Draw the folder, with the site's own cleaner
        folder watch [dir]         Push on save — editor on one side, your page on the other
        folder sign [dir]          Seal the folder into your signed feed
        folder verify [dir]        Check the folder against its signature
        folder export [dir] [out]  A static copy any file server can host
        folder goodbye [--message]
                                   Close this feed (tombstone, does not undo)
        folder prune <name|key>    Drop somebody's replica off this disk
        identity create            A new account: a keypair on this machine
        identity join <key>        A second workstation under an existing account
        identity show              Who this machine speaks for
        identity backup            The master key, for paper
        identity device-add <key>  Authorise a device (master-signed)
        identity device-revoke <key>
                                   Cut a device off
        identity rotate            Hand signing to a fresh key (master-signed)
        identity recover           Reclaim a lost account via your friends
        identity endorse <feed> <seq> <prev> <new-master>
                                   Vouch for a friend's recovery, as their friend
        identity prove '<challenge>'  Sign the studio's ownership challenge with your master
        peer serve [--relay|--relay-open]  Answer sync requests (this machine's server)
        peer address [--host HOST] [--port PORT]  Check and print a copy-paste share command
        peer add <key> <name>      Follow somebody: peer add <hex> ron --at host:port
        peer list                  Who you follow, and where they were last seen
        peer remove <name|key>     Unfollow
        peer sync [name|key]       Pull follows up to date
        peer keygen                A device key for a node operator
        peer bootstrap             Follow the shipped seeds, then sync
        peer status [name|key]     Discovery state, path and reachability per follow
        net up                     Join discovery: DHT, NAT probe, publish endpoint
        net down                   Leave discovery: release mappings, stop publishing
        net wait <who> --at relay  Wait at an open relay for one follow (unreachable meets unreachable)

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
      when "identity" then identity_command
      when "peer" then peer_command
      when "net" then net_command
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
      target = @argv.shift

      raise UsageError, "rate set needs a username and an opinion" if username.nil?

      unless %w[like dislike none].include?(opinion)
        raise UsageError, "say like, dislike or none — `none` takes your rating back"
      end

      # `rate set @wes like showcase/12` reacts to that rice rather than to the page. The
      # thing people react to is the thing that was posted; reaching only the page would be
      # reaching the wrong one.
      kind, id = target&.split("/", 2)
      if target && (kind.nil? || id.nil? || id !~ /\A\d+\z/)
        raise UsageError, "a target looks like showcase/12 — the kind, then the id"
      end

      rating = client.rate(username, opinion, kind, id)
      return Ui.raw(rating["raw"]) if @options[:json]

      Ui.wordmark
      Ui.section("rating")
      Ui.key_value("you said", rating["yours"] || "nothing")
      Ui.key_value("about", rating["target"])
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
      when "sign" then folder_sign
      when "verify" then folder_verify
      when "export" then folder_export
      when "goodbye" then folder_goodbye
      when "prune" then folder_prune
      else
        raise UsageError, "unknown folder command #{sub.inspect} — one of: #{FOLDER_COMMANDS.join(", ")}"
      end
    end

    # ---- identity -----------------------------------------------------------------------

    def identity_command
      sub = @argv.shift
      raise UsageError, "identity needs one of: #{IDENTITY_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "create" then identity_create
      when "join" then identity_join
      when "show" then identity_show
      when "backup" then identity_backup
      when "device-add" then identity_device_add
      when "device-revoke" then identity_device_revoke
      when "rotate" then identity_rotate
      when "recover" then identity_recover
      when "endorse" then identity_endorse
      when "prove" then identity_prove
      else
        raise UsageError, "unknown identity command #{sub.inspect} — one of: #{IDENTITY_COMMANDS.join(", ")}"
      end
    end

    def identity_prove
      challenge = @argv.shift.to_s
      unless challenge.match?(%r{\Aricespace-link-v1:https?://[^\s]+:\d+:[0-9a-f]{64}:[0-9a-f]{64}\z})
        raise UsageError, "paste the exact ownership challenge from your trusted studio, quoted"
      end
      identity = p2p_identity
      passphrase = P2p::Keys.ask_passphrase("the master passphrase")
      signature = P2p::Keys.sign(identity.unlock_master(passphrase), challenge)
      if @options[:json]
        Ui.raw({ "proof" => signature })
      else
        Ui.notice("Paste this ownership proof into the same studio; it expires after 10 minutes:")
        puts signature
      end
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def identity_create
      dir = Config::DIRECTORY
      if P2p::Identity.exists?(dir)
        raise UsageError, "this machine already speaks for somebody — see `ricespace identity show`"
      end

      name = option("--name") || hostname
      Ui.wordmark
      Ui.notice("A new account lives in its keypair. The master key stays on this machine;")
      Ui.key_value("note", "write the backup down when it is printed — it is the only copy")

      master_pass = P2p::Keys.ask_passphrase("a passphrase for the master key")
      raise UsageError, "the master key needs a passphrase" if master_pass.empty?
      if (advice = P2p::Keys.passphrase_advice(master_pass))
        raise UsageError, "that passphrase is too weak for the master key: #{advice}"
      end

      confirm = P2p::Keys.ask_passphrase("again, to be sure")
      raise UsageError, "the two passphrases do not match" unless confirm == master_pass

      identity = P2p::Identity.create(
        dir: dir, device_name: name,
        master_passphrase: master_pass, device_passphrase: master_pass
      )

      # The first record: this device may sign for this feed. Without it the
      # device key is a stranger to its own account.
      master_secret = identity.unlock_master(master_pass)
      feed = P2p::Feed.new(identity.master_public)
      feed.append(P2p::Record.build(
        author: identity.master_public, signer: identity.master_public,
        seq: 1, prev: P2p::Record::GENESIS_PREV,
        kind: "device-add", body: { "device" => identity.device_public },
        sign_with: master_secret
      ))

      Ui.ok("Created.")
      Ui.key_value("account", identity.short_id)
      Ui.key_value("master", identity.master_public)
      Ui.key_value("device", "#{identity.device_name} (#{identity.device_public[0, 12]})")
      Ui.key_value("feed", "seq 1 — this device may sign")
    end

    # A second workstation under an existing account: this machine gets its own
    # device key and only the master's public half. The owner then authorises
    # the new device from a machine holding the master (`identity device-add`),
    # and sync carries the authorisation over.
    def identity_join
      master = @argv.shift
      raise UsageError, "identity join needs the account's master key" if master.nil?
      raise UsageError, "not a key" unless P2p::Keys.valid_public?(master)

      dir = Config::DIRECTORY
      if P2p::Identity.exists?(dir)
        raise UsageError, "this machine already speaks for somebody — see `ricespace identity show`"
      end

      name = option("--name") || hostname
      device_pass = P2p::Keys.ask_passphrase("a passphrase for this device's key")
      raise UsageError, "the device key needs a passphrase" if device_pass.empty?
      if (advice = P2p::Keys.passphrase_advice(device_pass))
        Ui.warn("weak passphrase: #{advice}")
      end

      identity = P2p::Identity.join(
        dir: dir, device_name: name,
        master_public: master, device_passphrase: device_pass
      )

      Ui.wordmark
      Ui.ok("Joined #{identity.short_id} as #{name}.")
      Ui.key_value("device", identity.device_public)
      Ui.key_value("next", "from the master machine: `identity device-add #{identity.device_public}`")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def identity_show
      identity = P2p::Identity.load(Config::DIRECTORY)
      feed = P2p::Feed.new(identity.master_public)
      result = feed.verify

      Ui.wordmark
      Ui.key_value("account", identity.short_id)
      Ui.key_value("master", identity.master_public)
      Ui.key_value("device", "#{identity.device_name} (#{identity.device_public[0, 12]})")
      Ui.key_value("feed", "seq #{result.state["seq"]}, #{result.ok? ? "clean" : "BROKEN: #{result.errors.first}"}")
      Ui.key_value("friends", result.state["friends"].size.to_s)
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # The master secret, to paper via a file — never the terminal. Shell
    # history, scrollback and screenshots are all copies you did not mean to
    # make; a 0600 file in a chosen path is one copy, made deliberately.
    def identity_backup
      out = option("--out")
      identity = P2p::Identity.load(Config::DIRECTORY)
      passphrase = P2p::Keys.ask_passphrase("the master passphrase")
      secrets = identity.backup(passphrase)

      Ui.wordmark
      if out
        path = Pathname.new(out)
        path.write(JSON.generate({ "master_public" => secrets["master_public"],
          "master_secret" => secrets["master_secret"] }) + "\n")
        path.chmod(0o600)
        Ui.ok("Backed up to #{path} (0600).")
        Ui.key_value("next", "print it, twice, then delete the file — paper, not disk")
      else
        Ui.notice("Write this down, on paper, in two places. It IS the account.")
        puts
        puts "  master public: #{secrets["master_public"]}"
        puts "  master secret: #{secrets["master_secret"]}"
        puts
        Ui.key_value("warning", "anybody holding the secret is you — no passphrase protects paper")
        Ui.key_value("better", "`identity backup --out paper.json` avoids terminal scrollback")
      end
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # ---- peer ---------------------------------------------------------------------------

    def peer_command
      sub = @argv.shift
      raise UsageError, "peer needs one of: #{PEER_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "serve" then peer_serve
      when "address" then peer_address
      when "add" then peer_add
      when "list" then peer_list
      when "remove" then peer_remove
      when "sync" then peer_sync
      when "keygen" then peer_keygen
      when "bootstrap" then peer_bootstrap
      when "status" then peer_status
      else
        raise UsageError, "unknown peer command #{sub.inspect} — one of: #{PEER_COMMANDS.join(", ")}"
      end
    end

    def net_command
      sub = @argv.shift
      raise UsageError, "net needs one of: #{NET_COMMANDS.join(", ")}" if sub.nil?

      case sub
      when "up" then net_up
      when "down" then net_down
      when "wait" then net_wait
      else
        raise UsageError, "unknown net command #{sub.inspect} — one of: #{NET_COMMANDS.join(", ")}"
      end
    end

    # Join internet discovery: bootstrap the DHT, characterise the NAT,
    # publish our endpoint slot. Prints what was learned and how.
    def net_up
      identity = p2p_identity
      port = (option("--port") || ENV["RICESPACE_PEER_PORT"] || P2p::Sync::DEFAULT_PORT).to_i
      publish = !@argv.include?("--no-publish")
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      Ui.wordmark
      dht = P2p::Net::Dht.new
      begin
        answered = dht.bootstrap
        Ui.key_value("discovery", "#{answered} DHT router(s) answered")
      rescue P2p::Error => error
        Ui.key_value("discovery", "unreachable (#{error.message})")
        Ui.key_value("note", "LAN sync and manual addresses still work")
        return
      ensure
        dht.close rescue nil
      end

      nat = P2p::Net::Nat.characterise(port: port)
      Ui.key_value("nat", nat.label)
      Ui.key_value("how", nat.detail)
      external = nat.external ? "#{nat.external["host"]}:#{nat.external["port"]}" : nil

      if publish
        addrs = [ external, "0.0.0.0:#{port}" ].compact.reject { |addr| addr.start_with?("0.0.0.0") }
        if addrs.empty?
          Ui.key_value("published", "nothing — no observed address; serving still works for outbound sync")
        else
          record = P2p::Net::Endpoint.build(node: identity.master_public, device: identity.device_public,
            addrs: addrs, sign_with: private_hex)
          accepted = publish_slot(identity, record)
          P2p::Net::Discovery.load.note_published if accepted.positive?
          Ui.key_value("published", "#{accepted} DHT node(s) hold our endpoint (#{addrs.join(", ")})")
        end
      else
        Ui.key_value("published", "skipped (--no-publish)")
      end
      Ui.key_value("privacy", "slots expose addrs + keys, never feeds or follows — see peer status --privacy")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def publish_slot(identity, record)
      packed = P2p::Net::Endpoint.pack(record)
      dht = P2p::Net::Dht.new
      begin
        dht.bootstrap
        dht.publish(identity.device_public, identity.unlock_device(
          ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")), packed)
      rescue P2p::Error
        0
      ensure
        dht.close rescue nil
      end
    end

    def net_down
      Ui.wordmark
      Ui.ok("Left discovery — republication stops when peer serve stops.")
      Ui.key_value("note", "DHT slots expire within 2 h; mappings release on serve exit")
    end

    # Wait at an open rendezvous relay for one follow: ALLOC a ticket,
    # publish it in our own endpoint slot, serve the spliced session when
    # they JOIN. For the unreachable node that wants to be found.
    def net_wait
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      who = @argv.reject { |arg| arg.start_with?("--") }.first
      raise UsageError, "net wait needs who is coming: net wait <name|key> --at relay:port" if who.nil?
      pub = resolve_follow(peers, who) || (P2p::Keys.valid_public?(who) ? who : nil)
      raise UsageError, "not following #{who.inspect} — peer add it first" if pub.nil?
      relay_addr = option("--at") || shipped_relay
      raise UsageError, "no rendezvous relay — pass --at relay:port" if relay_addr.nil?

      host, port = relay_addr.split(":", 2)
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      Ui.wordmark
      control, secret = P2p::Net::Relay.alloc(host, port.to_i || P2p::Sync::DEFAULT_PORT,
        identity: identity, peers: peers, private_hex: private_hex,
        relay_pin: :none, store_root: P2p::Feed.root)
      Ui.key_value("relay", relay_addr)
      Ui.key_value("ticket", "#{secret[0, 8]}… (single-use, 5 min)")

      # Signal through our own slot: ticket naming them, at this relay.
      record = P2p::Net::Endpoint.build(node: identity.master_public, device: identity.device_public,
        addrs: [], rv: [ relay_addr ],
        ticket: { "relay" => relay_addr, "secret" => secret, "peer" => pub },
        sign_with: private_hex)
      accepted = publish_slot(identity, record)
      Ui.key_value("signalled", "#{accepted} DHT node(s) hold the ticket for #{P2p::Names.short(pub)}")

      Ui.notice("Waiting for #{P2p::Names.short(pub)} — Ctrl-C to stop.")
      session = P2p::Net::Relay.await_peer(control, secret, identity: identity,
        peers: peers, private_hex: private_hex, target_feed: pub,
        target_pin: dial_device_key(pub) || pub, store_root: P2p::Feed.root)
      Ui.ok("They arrived — serving.")
      session.serve_loop(peers: peers, store_root: P2p::Feed.root)
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def shipped_relay
      P2p::Net::Relays.list.first&.fetch("addr", nil)
    end

    # Per-follow discovery state: path, reachability, last sync.
    def peer_status
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      if @argv.include?("--privacy")
        Ui.wordmark
        Ui.notice("What DHT endpoint slots expose, honestly:")
        Ui.key_value("public", "master key, device key, dial addresses, relay addresses, timestamps")
        Ui.key_value("never", "feed contents, follow lists, petnames, sequence numbers")
        Ui.key_value("visible to", "anyone who derives the slot target — discovery metadata is connection metadata")
        return
      end
      who = @argv.reject { |arg| arg.start_with?("--") }.first
      pubs = if who
        pub = resolve_follow(peers, who) || (P2p::Keys.valid_public?(who) ? who : nil)
        raise UsageError, "not following #{who.inspect}" if pub.nil?

        [ pub ]
      else
        peers.follows.keys
      end

      Ui.wordmark
      Ui.key_value("you", identity.short_id)
      state = sync_state
      pubs.each do |pub|
        name = peers.petname_for(pub)
        label = name.empty? ? P2p::Names.short(pub) : "#{name} [#{P2p::Names.short_pair(pub)}]"
        entry = peers.endpoint_for(pub)
        last = state[pub]
        parts = []
        parts << "path=#{last ? last["path"] : "never synced"}"
        parts << "last=#{last ? Time.at(last["at"]).utc.strftime("%Y-%m-%d %H:%M UTC") : "never"}"
        parts << "addrs=#{(Array(entry["addrs"]) + peers.addrs_for(pub)).uniq.size}"
        parts << "slot=#{entry["ep_at"] ? "#{((Time.now.to_i - entry["ep_at"]) / 60).to_i}m old" : "none"}"
        Ui.key_value(label, parts.join(" · "))
      end
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # A fresh device key for a node operator: the public half goes on the
    # /peers page, the secret into RICESPACE_NODE_SECRET_FILE. Printed once —
    # there is nowhere it is stored.
    def peer_keygen
      keypair = P2p::Keys.generate

      Ui.wordmark
      Ui.notice("A device key for a node. The secret lives in one file on that node.")
      puts
      puts "  public: #{keypair[:public_hex]}"
      puts "  secret: #{keypair[:private_hex]}"
      puts
      Ui.key_value("node", "put the secret in RICESPACE_NODE_SECRET_FILE, mode 0600")
      Ui.key_value("owner", "authorise the public half with `identity device-add`")
    end

    def peer_address
      identity = p2p_identity
      host = option("--host")
      port = option("--port") || ENV["RICESPACE_PEER_PORT"] || P2p::Sync::DEFAULT_PORT
      result = P2p::Address.report(public_key: identity.master_public,
        device_key: identity.device_public, host: host, port: port)
      return Ui.raw(result) if @options[:json]

      Ui.wordmark
      Ui.key_value("address", result["address"])
      Ui.key_value("checked", result["listener"])
      Ui.key_value("scope", result["scope"])
      Ui.notice("Send this command to your friend (rename `friend` if they want):")
      puts result["command"]
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def peer_serve
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      port = (option("--port") || ENV["RICESPACE_PEER_PORT"] || P2p::Sync::DEFAULT_PORT).to_i
      lan = !@argv.include?("--no-lan")
      relay = if @argv.include?("--relay-open")
        P2p::Net::Relay::Registry.new(open: true)
      elsif @argv.include?("--relay")
        P2p::Net::Relay::Registry.new
      end
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      Ui.wordmark
      Ui.notice("Serving #{identity.short_id} on port #{port} — Ctrl-C to stop.")
      Ui.key_value("follows", peers.follows.size.to_s)
      Ui.key_value("lan", lan ? "announcing + listening" : "off")
      Ui.key_value("relay", relay ? (relay.open? ? "OPEN rendezvous for strangers by ticket (capped, content-opaque)" : "bridging for consenting callers (capped, content-opaque)") : "off — pass --relay to bridge, --relay-open for rendezvous")
      Ui.key_value("wire", "TLS, pinned to known keys — strangers fail closed")

      P2p::Sync.serve(port: port, identity: identity, peers: peers,
        private_hex: private_hex, lan: lan, relay: relay).run
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def peer_add
      key = @argv.shift
      petname = @argv.shift
      raise UsageError, "peer add needs a key and a petname: peer add <hex> ron --at host:port" if
        key.nil? || petname.nil?

      at = option("--at")
      addrs = at ? [ at ] : []
      peers = P2p::Peers.load(Config::DIRECTORY)
      device = option("--device")
      peers.add(key, petname: petname, addrs: addrs, device: device)

      record_follow(key, petname)

      Ui.wordmark
      Ui.ok("Following #{P2p::Names.display(petname, key)}.")
      Ui.key_value("at", addrs.first || "(no address yet — add one with --at, or meet on LAN)")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # First contact: follow every shipped seed that has an address, then
    # sync. Seeds name keys, not live hosts — addresses rot, gossip and the
    # beacon correct them, the TLS pin still has to pass. Following is still
    # explicit afterwards: bootstrap follows seeds, nothing else, ever.
    def peer_bootstrap
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      seeds = P2p::Seeds.list
      raise UsageError, "no seeds shipped with this client" if seeds.empty?

      Ui.wordmark
      added = 0
      seeds.each do |seed|
        next if peers.follow?(seed["key"])

        name = seed["petname"].empty? ? P2p::Names.short(seed["key"]) : seed["petname"]
        peers.add(seed["key"], petname: name, addrs: seed["addrs"])
        record_follow_quiet(identity, seed["key"], name)
        added += 1
        Ui.key_value("following", "#{P2p::Names.display(name, seed["key"])}#{seed["addrs"].empty? ? " (no address — gossip may find one)" : ""}")
      end
      Ui.ok(added.zero? ? "Seeds already followed." : "Following #{added} seed(s).")

      @argv = []
      peer_sync
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # record_follow without the passphrase round-trip per seed: one unlock,
    # one record per follow would fork the seq — instead a single `friend`
    # per seed is wrong too. Simplest honest shape: sign each follow.
    def record_follow_quiet(identity, pub, petname)
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase (once, for #{P2p::Names.short(pub)})")
      ENV["RICESPACE_PASSPHRASE"] = passphrase
      record_follow(pub, petname)
    end

    def peer_list
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)

      Ui.wordmark
      Ui.key_value("you", identity.short_id)
      if peers.follows.empty?
        puts "  #{Ui.send(:dim, "following nobody — peer add <key> <name>, or peer bootstrap")}"
      else
        peers.follows.each do |pub, entry|
          feed = P2p::Feed.new(pub)
          result = feed.verify
          state = result.ok? ? "seq #{result.state["seq"]}" : "BROKEN: #{result.errors.first}"
          name = entry.is_a?(Hash) ? entry["petname"] : ""
          addrs = entry.is_a?(Hash) ? Array(entry["addrs"]) : []
          Ui.key_value(name.empty? ? P2p::Names.short(pub) : name,
            "#{P2p::Names.short_pair(pub)} · #{state} · #{addrs.first || "no address"}")
        end
      end

      hints = peers.hints.reject { |pub, _| peers.follow?(pub) }
      unless hints.empty?
        Ui.section("heard about (not followed)")
        hints.each do |pub, addrs|
          Ui.key_value(P2p::Names.short(pub),
            "#{P2p::Names.short_pair(pub)} · #{Array(addrs).first || "no address"} · peer add to follow")
        end
      end
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def peer_remove
      who = @argv.shift
      raise UsageError, "peer remove needs a petname or a key" if who.nil?

      peers = P2p::Peers.load(Config::DIRECTORY)
      pub = resolve_follow(peers, who)
      raise UsageError, "not following #{who.inspect}" if pub.nil?

      peers.remove(pub)
      record_unfollow(pub)

      Ui.wordmark
      Ui.ok("Unfollowed #{P2p::Names.short(pub)}.")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # The dial ladder per follow: manual --at, then stored addrs, then DHT
    # endpoint slots, then relay bridges. A pin failure fails the rung, never
    # the ladder — and never falls back to unauthenticated.
    def peer_sync
      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      who = @argv.reject { |arg| arg.start_with?("--") }.first

      dials = peers.dial_list
      pubs = if who
        pub = resolve_follow(peers, who) || (P2p::Keys.valid_public?(who) ? who : nil)
        raise UsageError, "not following #{who.inspect} — peer add it first" if pub.nil?

        [ pub ]
      else
        peers.follows.keys
      end

      dht = sync_dht
      targets = pubs.flat_map do |pub|
        ladder_for(peers, pub, dials, dht, own_pub: identity.master_public)
      end

      if targets.empty?
        Ui.wordmark
        Ui.notice("Nobody to sync with — no addresses. peer add --at, meet on LAN, or run net up.")
        return
      end

      Ui.wordmark
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      total = 0
      pushed_total = 0
      learned_total = 0
      shown = {}
      done = {}
      targets.each do |pub, addr, via, kind|
        next if done[pub]

        host, port = addr.split(":", 2)
        begin
          gained = if kind == :relay
            dial_via_relay(pub, addr, via, identity, peers, private_hex)
          elsif kind == :rendezvous
            dial_via_rendezvous(pub, via, identity, peers, private_hex)
          else
            # Pinned to the serving node's key: the cert must carry a key of
            # the account at this address, or the session dies before HELLO.
            # A dial entry pointing at an impostor fails here.
            device_key = kind == :dht ? via[:pin] : dial_device_key(via)
            P2p::Sync.pull(host, port || P2p::Sync::DEFAULT_PORT,
              identity: identity, peers: peers, private_hex: private_hex,
              expected_key: device_key || (kind == :dht ? pub : via))
          end
          pushed_total += gained.delete("!pushed").to_i
          learned_total += gained.delete("!addrs").to_i
          count = gained.values.sum
          total += count
          shown[pub] = (shown[pub] || 0) + count
          done[pub] = true
          note_sync_path(pub, kind, addr)
        rescue P2p::Error => error
          shown[pub] = shown.fetch(pub, "#{path_word(kind)} unreachable (#{error.message})")
        end
      end
      shown.each do |pub, count|
        Ui.key_value(P2p::Names.short(pub), count.is_a?(Integer) ? (count.zero? ? "up to date" : "+#{count} records") : count)
      end
      Ui.key_value("pushed", "#{pushed_total} of your records accepted") if pushed_total.positive?
      Ui.key_value("learned", "#{learned_total} new addresses via gossip") if learned_total.positive?
      Ui.ok("Synced #{total} new records.") unless total.zero? && pushed_total.zero?
    rescue P2p::Error => error
      raise UsageError, error.message
    ensure
      dht&.close
    end

    # Manual addrs, then every other follow's addr as replica candidates,
    # then DHT resolution (manual always wins: it leads the ladder).
    def ladder_for(peers, pub, dials, dht, own_pub: nil)
      manual = dials.select { |candidate, _, _| candidate == pub }
      replicas = dials.reject { |candidate, _, _| candidate == pub }.map { |_, addr, via| [ pub, addr, via, :replica ] }
      ladder = manual.map { |candidate, addr, via| [ candidate, addr, via, :manual ] } + replicas
      return ladder if dht.nil?

      begin
        P2p::Net::Discovery.resolve(peers, pub, dht: dht, own_pub: own_pub).each do |candidate|
          next if candidate[:via] != :rendezvous &&
            ladder.any? { |_, addr, _, _| addr == candidate[:addr] }

          if candidate[:via] == :relay
            ladder << [ pub, candidate[:addr],
              { pin: candidate[:pin], relay_feed: candidate[:relay_feed] }, :relay ]
          elsif candidate[:via] == :rendezvous
            ladder << [ pub, candidate[:addr],
              { pin: candidate[:pin], ticket: candidate[:ticket] }, :rendezvous ]
          else
            ladder << [ pub, candidate[:addr], { pin: candidate[:pin] }, :dht ]
          end
        end
      rescue P2p::Error
        nil
      end
      ladder
    end

    def path_word(kind)
      case kind
      when :manual then "manual address"
      when :replica then "replica"
      when :dht then "discovered address"
      when :relay then "relay"
      when :rendezvous then "rendezvous"
      else "address"
      end
    end

    # JOIN the ticket the follow signalled: the relay is a stranger, so its
    # control leg is unpinned — authentication is end-to-end (target pin)
    # plus the ticket secret itself, which only the follow's slot gave us.
    def dial_via_rendezvous(pub, info, identity, peers, private_hex)
      ticket = info[:ticket]
      host, port = ticket["relay"].split(":", 2)
      session = P2p::Net::Relay.join(host, port.to_i || P2p::Sync::DEFAULT_PORT,
        ticket["secret"], identity: identity, peers: peers, private_hex: private_hex,
        target_feed: pub, target_pin: info[:pin], relay_pin: :none,
        store_root: P2p::Feed.root)
      begin
        pushed = session.push_own
        learned = session.exchange_addrs(peers: peers)
        gained = session.pull(peers: peers)
        gained["!pushed"] = pushed if pushed.positive?
        gained["!addrs"] = learned.size if learned.any?
        gained
      ensure
        session.close
      end
    end

    # One DHT client per sync run, bootstrapped once. Silent when discovery
    # is unreachable — the ladder simply has fewer rungs.
    def sync_dht
      dht = P2p::Net::Dht.new
      dht.bootstrap
      dht
    rescue P2p::Error
      nil
    end

    def dial_via_relay(pub, relay_addr, info, identity, peers, private_hex)
      host, port = relay_addr.split(":", 2)
      relay_pin = dial_device_key(info[:relay_feed]) || info[:relay_feed]
      session = P2p::Net::Relay.dial(host, port.to_i || P2p::Sync::DEFAULT_PORT,
        identity: identity, peers: peers, private_hex: private_hex,
        target_feed: pub, target_pin: info[:pin], relay_pin: relay_pin)
      begin
        pushed = session.push_own
        learned = session.exchange_addrs(peers: peers)
        gained = session.pull(peers: peers)
        gained["!pushed"] = pushed if pushed.positive?
        gained["!addrs"] = learned.size if learned.any?
        gained
      ensure
        session.close
      end
    end

    def note_sync_path(pub, kind, addr)
      state = sync_state
      state[pub] = { "path" => kind.to_s, "addr" => addr, "at" => Time.now.to_i }
      save_sync_state(state)
    end

    def sync_state
      file = Pathname.new(Config::DIRECTORY.to_s).join("sync_state.json")
      return {} unless file.file?

      JSON.parse(file.read).then { |data| data.is_a?(Hash) ? data : {} }
    rescue JSON::ParserError
      {}
    end

    def save_sync_state(state)
      dir = Pathname.new(Config::DIRECTORY.to_s)
      dir.mkpath
      file = dir.join("sync_state.json")
      temp = Pathname.new("#{file}.new")
      temp.write(JSON.pretty_generate(state) + "\n")
      temp.chmod(0o600)
      temp.rename(file)
    rescue SystemCallError
      nil
    end

    # The device key to pin when dialing an account's own address: the live
    # device learned from their feed, else their master key. Either way the
    # cert must carry a key belonging to that account — never just any cert.
    def dial_device_key(pub)
      feed = P2p::Feed.new(pub)
      if feed.records.empty?
        entry = P2p::Peers.load(Config::DIRECTORY).follows[pub]
        return entry["device"] if entry.is_a?(Hash) && P2p::Keys.valid_public?(entry["device"].to_s)
      end
      result = feed.verify
      return nil unless result.ok?

      devices = result.state["devices"].reject { |_key, device| device["revoked"] }
      live = devices.keys.first
      live == pub ? nil : live
    rescue P2p::Error
      nil
    end

    # Signing the follow into our own feed, so any verifier of the feed sees
    # the same friends list we sync by. The device signs; follows are content,
    # not account management.
    def record_follow(pub, petname)
      identity = p2p_identity
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = identity.unlock_device(passphrase)
      feed = P2p::Feed.new(identity.master_public)
      feed.append(P2p::Record.build(
        author: identity.master_public, signer: identity.device_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "friend", body: { "peer" => pub.to_s, "petname" => petname.to_s, "action" => "add" },
        sign_with: private_hex
      ))
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def record_unfollow(pub)
      identity = p2p_identity
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = identity.unlock_device(passphrase)
      feed = P2p::Feed.new(identity.master_public)
      feed.append(P2p::Record.build(
        author: identity.master_public, signer: identity.device_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "friend", body: { "peer" => pub.to_s, "action" => "remove" },
        sign_with: private_hex
      ))
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def resolve_follow(peers, who)
      return who if P2p::Keys.valid_public?(who.to_s)

      peers.follows.each do |pub, entry|
        name = entry.is_a?(Hash) ? entry["petname"].to_s : ""
        return pub if name == who.to_s
      end
      nil
    end

    # Authorise a device to sign for this feed: a node, a second workstation,
    # anything holding its own key. Master-signed — this is the owner speaking,
    # which is why it asks for the master passphrase rather than the device's.
    def identity_device_add
      device = @argv.shift
      raise UsageError, "identity device-add needs the device's key" if device.nil?
      raise UsageError, "not a key" unless P2p::Keys.valid_public?(device)

      identity = p2p_identity
      master_secret = identity.unlock_master(P2p::Keys.ask_passphrase("the master passphrase"))
      feed = P2p::Feed.new(identity.master_public)
      record = P2p::Record.build(
        author: identity.master_public, signer: identity.master_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "device-add", body: { "device" => device },
        sign_with: master_secret
      )
      feed.append(record)

      Ui.wordmark
      Ui.ok("Authorised #{P2p::Canonical.short_id(device)} at seq #{record["seq"]}.")
      Ui.key_value("note", "sync to carry it — the node sees it on its next import")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # Cut a device off: it signed until this seq, and nothing past it verifies.
    # The cutoff is now rather than zero, so records it signed while it was
    # yours keep verifying.
    def identity_device_revoke
      device = @argv.shift
      raise UsageError, "identity device-revoke needs the device's key" if device.nil?
      raise UsageError, "not a key" unless P2p::Keys.valid_public?(device)

      identity = p2p_identity
      master_secret = identity.unlock_master(P2p::Keys.ask_passphrase("the master passphrase"))
      feed = P2p::Feed.new(identity.master_public)
      record = P2p::Record.build(
        author: identity.master_public, signer: identity.master_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "device-revoke", body: { "device" => device, "cutoff_seq" => feed.next_seq },
        sign_with: master_secret
      )
      feed.append(record)

      Ui.wordmark
      Ui.ok("Revoked #{P2p::Canonical.short_id(device)} — nothing from seq #{record["seq"]} verifies.")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # Hand signing to a fresh key: the old master goes quiet from this seq on.
    # The new master is generated here and its secret printed once — back it up
    # the same hour, because from this record on it IS the account.
    def identity_rotate
      identity = p2p_identity
      master_secret = identity.unlock_master(P2p::Keys.ask_passphrase("the master passphrase"))

      fresh = P2p::Keys.generate
      feed = P2p::Feed.new(identity.master_public)
      record = P2p::Record.build(
        author: identity.master_public, signer: identity.master_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "rotation", body: { "new_master" => fresh[:public_hex] },
        sign_with: master_secret
      )
      feed.append(record)

      Ui.wordmark
      Ui.ok("Rotated at seq #{record["seq"]} — the old master is quiet from here on.")
      puts
      puts "  new master public: #{fresh[:public_hex]}"
      puts "  new master secret: #{fresh[:private_hex]}"
      puts
      Ui.key_value("warning", "back the secret up now — it is the account from this seq on")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # Reclaim a lost account: a successor key announces itself with your
    # friends' signatures. The ceremony is deliberately manual — each friend
    # runs `identity endorse` on their own machine, and you carry the
    # `friend-key:signature` pairs back here. Majority of the friends on the
    # feed, and only friends with tenure count (keys stuffed during the attack
    # cannot elect it).
    def identity_recover
      identity = p2p_identity
      feed = P2p::Feed.new(identity.master_public)
      result = feed.verify
      friends = result.state["friends"]
      raise UsageError, "this feed names no friends — nobody can vouch for it" if friends.empty?

      successor = P2p::Keys.generate
      seq = feed.next_seq
      body = { "new_master" => successor[:public_hex] }

      pairs = @argv.reject { |arg| arg.start_with?("--") }
      if pairs.empty?
        Ui.wordmark
        Ui.notice("Each friend runs this on their own machine:")
        puts
        puts "  ricespace identity endorse #{identity.master_public} #{seq} #{feed.prev_hash} #{successor[:public_hex]}"
        puts
        Ui.key_value("needed", "a majority of #{friends.size} friends, with tenure")
        Ui.key_value("then", "re-run as: `identity recover friend-key:signature …`")
        Ui.key_value("successor", successor[:public_hex])
        Ui.key_value("keep", "this key — it announces itself in the recovery")
        puts
        puts "  successor secret: #{successor[:private_hex]}"
        return
      end

      endorsements = pairs.filter_map do |pair|
        friend, sig = pair.split(":", 2)
        next if friend.nil? || sig.nil?
        next unless P2p::Keys.valid_public?(friend) && sig.match?(/\A[0-9a-f]{128}\z/i)

        { "friend" => friend.downcase, "sig" => sig.downcase }
      end
      raise UsageError, "no usable friend-key:signature pairs" if endorsements.empty?

      record = P2p::Record.build(
        author: identity.master_public, signer: successor[:public_hex],
        seq: seq, prev: feed.prev_hash,
        kind: "recovery",
        body: body.merge("endorsements" => endorsements),
        sign_with: successor[:private_hex]
      )
      begin
        feed.append(record)
      rescue P2p::Error, P2p::ChainError => error
        raise UsageError, "the recovery was refused: #{error.message}"
      end

      Ui.wordmark
      Ui.ok("Recovered at seq #{record["seq"]} — #{successor[:public_hex][0, 12]} speaks from here on.")
      puts
      puts "  new master public: #{successor[:public_hex]}"
      puts "  new master secret: #{successor[:private_hex]}"
      puts
      Ui.key_value("warning", "back the secret up now — and tell your follows to sync")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # Vouch for a friend's recovery: sign their successor announcement with
    # your MASTER key — the owner's friends list names master keys, and the
    # verifier checks each endorsement against the friend it names. A device
    # signature would never verify. Prints `friend-key:signature` for them to
    # carry back. Only sign when you actually know them; your signature is
    # their account.
    def identity_endorse
      feed_key, seq_s, prev, new_master = @argv.shift(4)
      unless P2p::Keys.valid_public?(feed_key.to_s) && seq_s.to_s.match?(/\A\d+\z/) &&
          prev.to_s.match?(/\A[0-9a-f]{64}\z/i) && P2p::Keys.valid_public?(new_master.to_s)
        raise UsageError, "endorse needs: identity endorse <feed-key> <seq> <prev-hash> <new-master-key>"
      end

      identity = p2p_identity
      master_secret = begin
        identity.unlock_master(P2p::Keys.ask_passphrase("the master passphrase (endorsements are master-signed)"))
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      bytes = P2p::Canonical.signing_bytes(
        author: feed_key.downcase, seq: seq_s.to_i, prev: prev.downcase,
        kind: "recovery", body: { "new_master" => new_master.downcase }
      )
      sig = P2p::Keys.sign(master_secret, bytes)

      Ui.wordmark
      Ui.ok("Endorsed #{P2p::Canonical.short_id(new_master)} for #{P2p::Canonical.short_id(feed_key)}.")
      puts
      puts "  #{identity.master_public}:#{sig}"
      puts
      Ui.key_value("next", "hand that line to your friend — it goes into their `identity recover`")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def hostname
      require "socket"
      Socket.gethostname.split(".").first
    rescue StandardError
      "laptop"
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

    def folder_sign
      dir = @argv.reject { |a| a.start_with?("--") }.first || "."
      everything = @argv.include?("--all")
      folder = Folder.read(dir)

      identity = p2p_identity
      passphrase = P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      feed = P2p::Feed.new(identity.master_public)
      Ui.wordmark
      if everything
        records = folder.sign_all(feed: feed, private_hex: private_hex, device_public: identity.device_public)
        kinds = records.map { |record| "#{record["kind"]} #{record["seq"]}" }.join(", ")
        Ui.ok("Signed #{records.size} records — #{kinds}.")
      else
        record = folder.sign(feed: feed, private_hex: private_hex, device_public: identity.device_public)
        Ui.ok("Signed seq #{record["seq"]} — #{P2p::Record.hash_of(record)[0, 12]}.")
      end
      Ui.key_value("account", identity.short_id)
      Ui.key_value("envelope", File.join(dir, Folder::ENVELOPE))
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    def folder_verify
      dir = @argv.reject { |a| a.start_with?("--") }.first || "."
      folder = Folder.read(dir)
      record = folder.verify!

      Ui.wordmark
      Ui.ok("The folder is what #{P2p::Canonical.short_id(record["author"])} signed.")
      Ui.key_value("seq", record["seq"].to_s)
      Ui.key_value("record", P2p::Record.hash_of(record))
      Ui.key_value("files", Array(record.dig("body", "files")&.keys).size.to_s)
    end

    def folder_export
      args = @argv.reject { |a| a.start_with?("--") }
      dir = args[0] || "."
      out = args[1] || "#{dir}-export"
      folder = Folder.read(dir)

      begin
        folder.verify!
      rescue UsageError => error
        raise UsageError, "not exporting an unsigned folder: #{error.message}"
      end

      target = folder.export_to(out)

      Ui.wordmark
      Ui.ok("Exported.")
      Ui.key_value("to", target.to_s)
      Ui.key_value("serve", "cd #{target} && ruby -run -e httpd . -p 8000")
    end

    # Close this feed: a tombstone asks honest peers to drop the body, and
    # nothing after it verifies. The records stay (proof beats absence), the
    # page is gone. This does not undo — same as closing the account.
    def folder_goodbye
      message = option("--message") || @argv.reject { |a| a.start_with?("--") }.first
      identity = p2p_identity
      passphrase = ENV["RICESPACE_PASSPHRASE"] || P2p::Keys.ask_passphrase("the device passphrase")
      private_hex = begin
        identity.unlock_device(passphrase)
      rescue P2p::Error => error
        raise UsageError, error.message
      end

      feed = P2p::Feed.new(identity.master_public)
      body = {}
      body["message"] = message.to_s[0, 140] unless message.nil?
      record = P2p::Record.build(
        author: identity.master_public, signer: identity.device_public,
        seq: feed.next_seq, prev: feed.prev_hash,
        kind: "tombstone", body: body,
        sign_with: private_hex
      )
      feed.append(record)

      Ui.wordmark
      Ui.ok("Said goodbye at seq #{record["seq"]} — honest peers drop the page.")
      Ui.key_value("note", "replicas keep the proof; nothing new verifies after this")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # Drop a replicated feed from this machine: records, assets, the directory.
    # Your own feed is refused — `folder goodbye` closes it, `prune` is for
    # other people's copies aging off your disk. Honest and explicit:
    # retention is otherwise forever-by-default.
    def folder_prune
      who = @argv.reject { |a| a.start_with?("--") }.first
      raise UsageError, "prune needs a petname or a key" if who.nil?

      identity = p2p_identity
      peers = P2p::Peers.load(Config::DIRECTORY)
      pub = resolve_follow(peers, who) || (P2p::Keys.valid_public?(who) ? who : nil)
      raise UsageError, "no feed for #{who.inspect} on this machine" if pub.nil?
      raise UsageError, "that is your own feed — `folder goodbye` closes it" if pub == identity.master_public

      feed = P2p::Feed.new(pub)
      dir = feed.dir
      count = dir.directory? ? dir.children.count { |child| child.file? } : 0
      require "fileutils"
      FileUtils.rm_rf(dir) if dir.directory?

      Ui.wordmark
      Ui.ok("Pruned #{P2p::Names.short(pub)} — #{count} records off this disk.")
      Ui.key_value("note", "your follows are untouched; sync brings it back if you still follow them")
    rescue P2p::Error => error
      raise UsageError, error.message
    end

    # This machine's P2P identity, or a sentence saying it has none yet.
    def p2p_identity
      P2p::Identity.load(Config::DIRECTORY)
    rescue P2p::Error => error
      raise UsageError, error.message
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
