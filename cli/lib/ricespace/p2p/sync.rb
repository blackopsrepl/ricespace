# frozen_string_literal: true

require "json"
require "socket"
require "openssl"

module RiceSpace
  module P2p
    # The wire: TLS, newline-delimited JSON.
    #
    #   HELLO  { "node": <master-pub> }                  # minimal; no inventory
    #   HAVE   { "feed": <pub> } → HAVE { "feed", "seq" } # per-feed seq query
    #   WANT   { "feed", "from", "limit" } → GIVE { "feed", "records" }
    #   PUBLISH { "feed", "records" } → ACCEPTED { n }    # push own records up
    #   ADDR   { "addrs": { "<pub>": ["host:port"] } }   # gossip observed addrs
    #   NEED   { "sha256": [...] }                       # asset hashes wanted
    #   HAVE   { "assets": { "<sha256>": <bytesize|null> } }
    #   FETCH  { "sha256": "<hash>" }                   # one asset's bytes follow
    #   BYE    {}                                        # clean close
    #
    # Replication is follow-gated: we offer what we hold, we store only feeds we
    # follow (plus our own). Assets transfer only by explicit hash request, and
    # only within the local byte cap.
    module Sync
      MAGIC = "RS1"
      DEFAULT_PORT = 7676
      CONNECT_TIMEOUT = 5
      READ_TIMEOUT = 15
      # Small enough that a hostile line cannot eat the machine: the largest
      # legitimate message is a GIVE batch, and batches are capped below.
      MAX_LINE = 256_000
      # A session moves at most this many records and bytes before it is cut.
      # Generous for a sync, useless for exfiltration-by-persistence.
      MAX_RECORDS_PER_SESSION = 5_000
      MAX_BYTES_PER_SESSION = 256 * 1024 * 1024
      MAX_GIVE_BATCH = 200
      # Concurrent connections. Past it, newcomers wait — nobody gets a thread
      # for free, and nobody holds one forever (READ_TIMEOUT still applies).
      MAX_CONNECTIONS = 32
      # Per-address dials per minute on the serving side.
      RATE_PER_MINUTE = 20
      # How much of *others'* pictures this machine keeps. Own feed's assets are
      # always kept; replicas stop at the cap. Mirrors the site's STORAGE_LIMIT
      # idea, enforced at fetch rather than at rest.
      REPLICA_ASSET_CAP = 200 * 1024 * 1024

      def self.serve(port:, identity:, peers:, private_hex:, store_root: Feed.root, lan: true, relay: nil,
          auto_rendezvous: false, peers_loader: nil)
        Server.new(port: port, identity: identity, peers: peers, private_hex: private_hex,
          store_root: store_root, lan: lan, relay: relay, auto_rendezvous: auto_rendezvous,
          peers_loader: peers_loader)
      end

      # Pull every followed feed from one address. Returns {feed => new_records}.
      # `expected_key` pins the remote: the cert it presents must carry this
      # device key, or the session dies before HELLO. Nil means "any key I
      # already know" — the fail-closed default for LAN-discovered peers.
      # `publish` pushes our own new records first (NATed nodes contribute
      # through the connection they opened), then pulls. `gossip` exchanges
      # observed addresses so friend-of-friend works without a directory.
      def self.pull(host, port, identity:, peers:, private_hex:, expected_key: nil,
          store_root: Feed.root, publish: true, gossip: true)
        session = Session.connect(host, port, identity: identity, peers: peers,
          private_hex: private_hex, expected_key: expected_key, store_root: store_root)
        begin
          pushed = publish ? session.push_own(store_root: store_root) : 0
          learned = gossip ? session.exchange_addrs(peers: peers) : {}
          gained = session.pull(peers: peers, store_root: store_root)
          gained["!pushed"] = pushed if pushed.positive?
          gained["!addrs"] = learned.size if learned.any?
          gained
        ensure
          session.close
        end
      end

      class Session
        def initialize(socket:, identity:, store_root:, follows: nil)
          @socket = socket
          @identity = identity
          @store_root = store_root
          # Callable(pub) → bool: does the serving side hold this feed as a
          # follow or its own? Anything else lands in capped quarantine.
          @peers_follow = follows
          @records_moved = 0
          @bytes_moved = 0
        end

        def self.connect(host, port, identity:, peers:, private_hex:, expected_key: nil, store_root: Feed.root)
          addr = host.to_s
          tcp = nil
          begin
            Timeout.timeout(CONNECT_TIMEOUT) do
              tcp = TCPSocket.new(addr, port.to_i)
            end
          rescue StandardError => error
            raise Error, "could not reach #{addr}:#{port} (#{error.message})"
          end
          tcp.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

          connect_io(tcp, addr, identity: identity, peers: peers, private_hex: private_hex,
            expected_key: expected_key, store_root: store_root)
        end

        # TLS over any byte stream: a TCP socket or a relay-bridged one. The
        # pin check is identical — the bridge never weakens authentication.
        def self.connect_io(io, addr, identity:, peers:, private_hex:, expected_key: nil, store_root: Feed.root)
          addr = addr.to_s
          ssl = OpenSSL::SSL::SSLSocket.new(io, Tls.client_context(private_hex))
          ssl.hostname = addr
          begin
            Timeout.timeout(CONNECT_TIMEOUT) { ssl.connect }
          rescue StandardError => error
            io.close rescue nil
            raise Error, "TLS to #{addr} failed (#{error.message})"
          end

          presented = Tls.peer_key(ssl)
          if expected_key == :none
            # Explicitly unpinned control leg (stranger rendezvous relay):
            # the relay is never trusted, authentication lives end-to-end.
            # The caller opts in by passing :none — never a default.
          elsif expected_key
            unless presented.downcase == expected_key.to_s.downcase
              ssl.close rescue nil
              raise Error, "the peer is not who was dialed (pinned #{expected_key[0, 12]}, showed #{presented[0, 12]})"
            end
          elsif !Tls.known_key?(presented, identity: identity, peers: peers, store_root: store_root)
            ssl.close rescue nil
            raise Error, "the peer #{presented[0, 12]} is a stranger — follow it first"
          end

          session = new(socket: ssl, identity: identity, store_root: store_root)
          session.say_hello
          session.read_hello
          session
        end

        # TLS server role over a bridged stream: the rendezvous waiter
        # accepts while the joiner connects. Pin check identical.
        def self.accept_io(io, addr, identity:, peers:, private_hex:, expected_key: nil, store_root: Feed.root)
          addr = addr.to_s
          ssl = OpenSSL::SSL::SSLSocket.new(io, Tls.server_context(private_hex))
          begin
            Timeout.timeout(CONNECT_TIMEOUT) { ssl.accept }
          rescue StandardError => error
            io.close rescue nil
            raise Error, "TLS accept for #{addr} failed (#{error.message})"
          end

          begin
            presented = Tls.peer_key(ssl)
          rescue Error
            ssl.close rescue nil
            raise Error, "the peer showed no certificate"
          end
          if expected_key
            unless presented.downcase == expected_key.to_s.downcase
              ssl.close rescue nil
              raise Error, "the peer is not who was waited for (pinned #{expected_key[0, 12]}, showed #{presented[0, 12]})"
            end
          elsif !Tls.known_key?(presented, identity: identity, peers: peers, store_root: store_root)
            ssl.close rescue nil
            raise Error, "the peer #{presented[0, 12]} is a stranger — follow it first"
          end

          session = new(socket: ssl, identity: identity, store_root: store_root)
          session.say_hello
          session.read_hello
          session
        end

        def close
          send_line({ "type" => "BYE" }) rescue nil
          @socket.close rescue nil
        end

        # Minimal HELLO: who we are and nothing else. The full have-summary
        # used to ride here and leaked the whole follow graph to strangers —
        # now each side asks per feed after the key check passes.
        def say_hello
          send_line({ "type" => "HELLO", "magic" => MAGIC, "node" => @identity.master_public })
        end

        def read_hello
          message = read_line
          raise Error, "not a ricespace peer" unless message.is_a?(Hash) &&
            message["type"] == "HELLO" && message["magic"] == MAGIC

          @remote = message
        end

        attr_reader :remote

        def have_summary
          summary = {}
          root = Pathname.new(@store_root.to_s)
          return summary unless root.directory?

          root.children.select(&:directory?).each do |dir|
            feed = Feed.new(dir.basename.to_s, root: @store_root)
            head = feed.head
            summary[feed.author] = head ? head["seq"] : 0
          end
          summary
        end

        # Ask the remote per feed: HAVE states its seq, WANT fetches past ours,
        # in capped batches. Each side learns only the seqs of feeds the other
        # names — never a full inventory up front.
        def pull(peers:, store_root: Feed.root)
          wanted = [ @identity.master_public ] + peers.follows.keys
          gained = {}
          wanted.uniq.each do |pub|
            local = Feed.new(pub, root: store_root)
            local_seq = local.head&.fetch("seq", 0) || 0

            send_line({ "type" => "HAVE", "feed" => pub })
            message = read_line
            next unless message.is_a?(Hash) && message["type"] == "HAVE" && message["feed"] == pub

            remote_seq = message["seq"].to_i
            next if remote_seq <= local_seq

            cursor = local_seq
            while cursor < remote_seq
              check_budget!(0, 0)
              send_line({ "type" => "WANT", "feed" => pub, "from" => cursor, "limit" => MAX_GIVE_BATCH })
              batch = read_line
              break unless batch.is_a?(Hash) && batch["type"] == "GIVE" && batch["feed"] == pub

              records = Array(batch["records"])
              break if records.empty?

              added = local.merge(records)
              @records_moved += records.size
              gained[pub] = (gained[pub] || 0) + added
              cursor = records.map { |record| record["seq"].to_i }.max
              check_budget!(0, 0)
            end
            fetch_missing_assets(local, store_root)
          end
          gained
        end

        # Push our own feed's new records to the remote (it stores what it
        # follows, drops the rest — same gating as a pull, mirrored). This is
        # how a NATed node publishes: it can never be dialed, so it pushes
        # through the connection it opened. Returns records accepted.
        def push_own(store_root: Feed.root)
          feed = Feed.new(@identity.master_public, root: store_root)
          records = feed.records
          return 0 if records.empty?

          send_line({ "type" => "PUBLISH", "feed" => @identity.master_public,
            "from" => 0, "records" => records })
          message = read_line
          return 0 unless message.is_a?(Hash) && message["type"] == "ACCEPTED"

          message["n"].to_i
        end

        # Swap observed addresses: ours for follows, theirs for theirs. Only
        # keys both sides... no — any key either side names. Addresses are not
        # secrets (anyone dialable is public by definition); keys still verify
        # everything. Returns {pub => [addrs]} newly learned.
        def exchange_addrs(peers:, store_root: Feed.root)
          mine = {}
          peers.follows.each do |pub, entry|
            addrs = entry.is_a?(Hash) ? Array(entry["addrs"]) : []
            mine[pub] = addrs unless addrs.empty?
          end
          send_line({ "type" => "ADDR", "addrs" => mine })
          message = read_line
          return {} unless message.is_a?(Hash) && message["type"] == "ADDR"

          learned = {}
          their = message["addrs"].is_a?(Hash) ? message["addrs"] : {}
          their.each do |pub, addrs|
            next unless Keys.valid_public?(pub.to_s)

            fresh = Array(addrs).map(&:to_s).uniq - peers.addrs_for(pub)
            next if fresh.empty?

            merged = (peers.addrs_for(pub) + fresh).uniq
            if peers.follow?(pub)
              peers.set_addrs(pub, merged)
              learned[pub] = fresh
            else
              # Unknown keys ride along but are not followed — discovery, not
              # introduction. Stored as an unfollowed hint for `peer list`.
              peers.note_hint(pub, merged)
              learned[pub] = fresh
            end
          end
          learned
        end

        # Answer one peer for the life of the connection.
        def serve_loop(peers:, store_root: Feed.root, relay: nil)
          loop do
            check_budget!(0, 0)
            message = read_line
            break if message.nil?
            next unless message.is_a?(Hash)

            case message["type"]
            when "HAVE"
              serve_have(message, store_root)
            when "WANT"
              serve_want(message, store_root)
            when "PUBLISH"
              serve_publish(message, store_root)
            when "ADDR"
              serve_addr(message, peers, store_root)
            when "NEED"
              serve_need(message, store_root)
            when "FETCH"
              serve_fetch(message, store_root)
            when "BRIDGE"
              serve_bridge(message, peers, relay)
              break
            when "ALLOC"
              serve_alloc(relay)
              break
            when "JOIN"
              serve_join(message, relay)
              break
            when "BYTES", "HANGUP"
              serve_relayed(message, relay)
            when "BYE"
              break
            end
          end
        rescue Error
          nil
        end

        def send_line(object)
          @socket.write("#{JSON.generate(object)}\n")
        end

        def read_line(timeout: READ_TIMEOUT)
          line = nil
          Timeout.timeout(timeout) do
            # Byte-wise to the newline with a hard cap: SSLSocket#gets takes
            # no limit argument, and an uncapped line is the DoS.
            buffer = +""
            loop do
              char = @socket.read(1)
              break if char.nil?
              buffer << char
              raise Error, "the peer sent a line too long" if buffer.bytesize > MAX_LINE
              break if char == "\n"
            end
            line = buffer.empty? ? nil : buffer
          end
          return nil if line.nil?

          JSON.parse(line)
        rescue JSON::ParserError
          raise Error, "the peer spoke nonsense"
        rescue Timeout::Error
          raise Error, "the peer went quiet"
        end

        private

        # A caller asks this node to bridge bytes to another device.
        # Consent-only: without a relay registry (peer serve --relay) this
        # is NOROUTE. After BRIDGED the caller speaks raw TLS bytes framed in
        # BYTES messages; this side pumps them into a plain TCP connection to
        # the target's address. The target's own TLS handshake authenticates
        # the caller end-to-end — the relay never holds session keys.
        def serve_bridge(message, peers, relay)
          unless relay
            send_line({ "type" => "NOROUTE" })
            return
          end
          target = message["to"].to_s
          unless Keys.valid_public?(target)
            send_line({ "type" => "NOROUTE" })
            return
          end
          addr = relay_addr_for(target, peers)
          if addr.nil?
            send_line({ "type" => "NOROUTE" })
            return
          end
          host, port = addr.split(":", 2)
          tcp = nil
          begin
            Timeout.timeout(CONNECT_TIMEOUT) { tcp = TCPSocket.new(host.to_s, port.to_i) }
          rescue StandardError
            send_line({ "type" => "NOROUTE" })
            return
          end
          id = relay.create(@socket, tcp)
          send_line({ "type" => "BRIDGED", "session" => id })
          pump_bridge(id, relay, tcp)
        end

        # Public addresses first; LAN addresses as fallback. A connect to
        # an address the target itself published is an ordinary dial, not a
        # probe — it either connects or this returns nil (NOROUTE).
        def relay_addr_for(target, peers)
          candidates = []
          peers.follows.each do |pub, entry|
            next unless pub.to_s.downcase == target.downcase

            candidates.concat(Array(entry.is_a?(Hash) ? entry["addrs"] : []).map(&:to_s))
          end
          candidates.sort_by { |addr| Net::Endpoint.lan_only?(addr) ? 1 : 0 }.each do |addr|
            return addr unless addr.empty?
          end
          nil
        end

        # Pump framed TLS bytes between the caller (BYTES messages on the
        # control connection) and the target (raw TCP) — or, in control mode,
        # between two paired control connections (open rendezvous). Either
        # side closing or the cap/lifetime expiring ends the session.
        def pump_bridge(id, relay, tcp, control: false, leg: nil)
          require "base64"
          if control
            pump_paired(id, relay, leg || "join")
            return
          end
          loop do
            message = read_line
            break if message.nil?

            entry = relay.fetch(id)
            break if entry.nil?
            if !message.is_a?(Hash) || message["session"].to_s != id
              next if message.is_a?(Hash) && message["type"] == "BYE"
              next
            end
            if message["type"] == "HANGUP" || message["type"] == "BYE"
              break
            end
            next unless message["type"] == "BYTES"

            begin
              blob = Base64.strict_decode64(message["blob"].to_s)
            rescue ArgumentError
              break
            end
            begin
              relay.account(id, blob.bytesize)
            rescue Error
              break
            end
            begin
              tcp.write(blob) unless blob.empty?
            rescue StandardError
              break
            end
            reply = read_available(tcp)
            begin
              relay.account(id, reply.bytesize)
            rescue Error
              break
            end
            send_line({ "type" => "BYTES", "session" => id, "blob" => Base64.strict_encode64(reply) })
          end
        rescue Error
          nil
        ensure
          relay.drop(id)
          tcp&.close rescue nil
        end

        # One leg of a paired rendezvous session: frames read here shuttle
        # to the other leg's inbox; frames arriving there send back down.
        # Two threads (reader + writer) because TLS is full-duplex.
        def pump_paired(id, relay, leg)
          writer = Thread.new do
            loop do
              message = read_line
              break if message.nil?
              break if relay.fetch(id).nil?
              next unless message.is_a?(Hash) && message["session"].to_s == id
              break if message["type"] == "HANGUP" || message["type"] == "BYE"
              next unless message["type"] == "BYTES"

              blob = begin
                Base64.strict_decode64(message["blob"].to_s)
              rescue ArgumentError
                break
              end
              break if relay.shuttle(id, leg, blob).nil?
            end
          rescue StandardError
            nil
          end
          loop do
            break if relay.fetch(id).nil?

            blob = relay.take(id, leg, 1)
            if blob.nil?
              next unless relay.fetch(id).nil?

              break
            end
            begin
              send_line({ "type" => "BYTES", "session" => id, "blob" => Base64.strict_encode64(blob) })
            rescue StandardError
              break
            end
          end
          writer.kill
        rescue StandardError
          nil
        ensure
          writer&.kill
          relay.drop(id)
        end

        def read_available(io)
          reply = +"".b
          deadline = Time.now + READ_TIMEOUT
          loop do
            left = deadline - Time.now
            break if left <= 0

            ready, = IO.select([ io ], nil, nil, [ left, 0.2 ].min)
            break if ready.nil?

            begin
              chunk = io.read_nonblock(16_384)
              break if chunk.nil? || chunk.empty?

              reply << chunk
            rescue IO::WaitReadable
              break
            rescue StandardError
              break
            end
            break if reply.bytesize >= 16_384
          end
          reply
        end

        # Open rendezvous: the caller waits for a stranger holding the
        # ticket. No target, no pin, no prior contact — the relay only ever
        # shuttles BYTES frames between two control connections that both
        # dialled out to it. The end-to-end TLS handshake runs *inside* those
        # frames (same as the friend bridge), so the relay holds no keys.
        def serve_alloc(relay)
          unless relay&.open?
            send_line({ "type" => "NOROUTE" })
            return
          end
          waiter = nil
          begin
            waiter = relay.alloc_waiter
          rescue Error
            send_line({ "type" => "NOROUTE" })
            return
          end
          send_line({ "type" => "ALLOCATED", "secret" => waiter[:secret] })
          # Park: the JOIN leg pairs us (see serve_join) and wakes this with
          # a PAIRED notice; expiry or HANGUP ends the wait.
          paired = relay.await_pair(waiter[:secret], Net::Relay::TICKET_LIFETIME) do
            message = read_line(timeout: Net::Relay::TICKET_LIFETIME)
            break :hungup if message.nil?
            break :hungup if message.is_a?(Hash) && message["type"] == "HANGUP"
          end
          if paired.is_a?(Hash) && paired[:session]
            send_line({ "type" => "PAIRED", "session" => paired[:session] })
            pump_bridge(paired[:session], relay, nil, control: true, leg: waiter[:secret])
          end
        rescue StandardError
          nil
        end

        # The second stranger claims the ticket: pair the two control
        # connections under one session id; both sides then speak BYTES and
        # the relay shuttles frames between them.
        def serve_join(message, relay)
          unless relay&.open?
            send_line({ "type" => "NOROUTE" })
            return
          end
          id = relay.pair(message["secret"].to_s)
          if id.nil?
            send_line({ "type" => "NOROUTE" })
            return
          end
          send_line({ "type" => "JOINED", "session" => id })
          pump_bridge(id, relay, nil, control: true)
        end

        # A BYTES/HANGUP arriving on a connection with no live bridge (the
        # caller's leg died, or this node never consented): refuse, don't pump.
        def serve_relayed(message, relay)
          if message["type"] == "HANGUP"
            relay&.drop(message["session"].to_s)
            send_line({ "type" => "BYE" })
            return
          end
          send_line({ "type" => "NOROUTE" })
        end

        def check_budget!(records, bytes)
          @records_moved += records
          @bytes_moved += bytes
          if @records_moved > MAX_RECORDS_PER_SESSION || @bytes_moved > MAX_BYTES_PER_SESSION
            raise Error, "session budget spent — reconnect for more"
          end
        end

        def serve_have(message, store_root)
          pub = message["feed"].to_s
          feed = Feed.new(pub, root: store_root)
          head = feed.head
          send_line({ "type" => "HAVE", "feed" => pub, "seq" => head ? head["seq"] : 0 })
        end

        def serve_want(message, store_root)
          pub = message["feed"].to_s
          from = message["from"].to_i
          limit = [ message["limit"].to_i, 1 ].max
          limit = MAX_GIVE_BATCH if limit > MAX_GIVE_BATCH
          feed = Feed.new(pub, root: store_root)
          records = feed.records.select { |record| record["seq"] > from }.first(limit)
          check_budget!(records.size, 0)
          # Serve own feed to anyone; serve replicas only for feeds the remote
          # could plausibly want — which is everything we hold. Gating happens
          # on the *storing* side (we keep only what we follow).
          send_line({ "type" => "GIVE", "feed" => pub, "records" => records })
        end

        # A pushed feed: merge what verifies, count what stuck. Followed feeds
        # (and our own) store freely; unknown feeds land in quarantine — capped
        # bytes, verified the same, never rendered or ranked unless followed.
        # This is how a new node publishes at a stranger: the records wait on
        # disk until somebody follows the key. The spam bound is the
        # quarantine cap, not refusal.
        QUARANTINE_CAP = 50 * 1024 * 1024

        def serve_publish(message, store_root)
          pub = message["feed"].to_s
          records = Array(message["records"]).first(MAX_GIVE_BATCH * 5)
          check_budget!(records.size, 0)
          known = @peers_follow ? @peers_follow.call(pub) : true
          unless known
            return quarantined(store_root) do
              feed = Feed.new(pub, root: store_root)
              added = feed.merge(records)
              send_line({ "type" => "ACCEPTED", "n" => added })
            end
          end
          feed = Feed.new(pub, root: store_root)
          added = feed.merge(records)
          send_line({ "type" => "ACCEPTED", "n" => added })
        end

        # Run the block only if unknown-feed storage stays under cap; evict
        # oldest unknown feeds first. Followed feeds and our own never count.
        def quarantined(store_root)
          root = Pathname.new(store_root.to_s)
          yield
          return unless root.directory?

          over = quarantine_bytes(store_root) - QUARANTINE_CAP
          return if over <= 0

          unknown = root.children.select(&:directory?).sort_by { |dir| dir.mtime }
          unknown.each do |dir|
            break if over <= 0
            next if @peers_follow&.call(dir.basename.to_s)

            freed = dir.children.select(&:file?).sum(&:size)
            require "fileutils"
            FileUtils.rm_rf(dir)
            over -= freed
          end
        end

        def quarantine_bytes(store_root)
          root = Pathname.new(store_root.to_s)
          return 0 unless root.directory?

          root.children.select(&:directory?).sum do |dir|
            next 0 if @peers_follow&.call(dir.basename.to_s)

            dir.children.select(&:file?).sum(&:size)
          end
        end

        # Their addresses for our hint file; ours back. Mirrors exchange_addrs.
        def serve_addr(message, peers, _store_root)
          mine = {}
          peers.follows.each do |pub, entry|
            addrs = entry.is_a?(Hash) ? Array(entry["addrs"]) : []
            mine[pub] = addrs unless addrs.empty?
          end
          send_line({ "type" => "ADDR", "addrs" => mine })
          their = message["addrs"].is_a?(Hash) ? message["addrs"] : {}
          their.each do |pub, addrs|
            next unless Keys.valid_public?(pub.to_s)

            fresh = Array(addrs).map(&:to_s).uniq - peers.addrs_for(pub)
            next if fresh.empty?

            if peers.follow?(pub)
              peers.set_addrs(pub, (peers.addrs_for(pub) + fresh).uniq)
            else
              peers.note_hint(pub, fresh)
            end
          end
        end

        def serve_need(message, store_root)
          hashes = Array(message["sha256"]).map(&:to_s).first(64)
          answer = hashes.to_h do |hash|
            bytes = Assets.get(hash, store_root)
            [ hash, bytes ? bytes.bytesize : nil ]
          end
          send_line({ "type" => "HAVE", "assets" => answer })
        end

        def serve_fetch(message, store_root)
          hash = message["sha256"].to_s
          bytes = Assets.get(hash, store_root)
          if bytes.nil?
            send_line({ "type" => "HAVE", "assets" => { hash => nil } })
          else
            send_line({ "type" => "HAVE", "assets" => { hash => bytes.bytesize } })
            @socket.write(bytes)
          end
        end

        def fetch_missing_assets(feed, store_root)
          hashes = feed.records.flat_map do |record|
            next [] unless record["kind"] == "assets"

            Array(record["body"]["files"]).filter_map { |file| file["sha256"] if file.is_a?(Hash) }
          end.uniq.reject { |hash| Assets.have?(hash, store_root) }
          return if hashes.empty?

          # Cap: own feed's pictures always; others' stop at the replica budget.
          others_bytes = Assets.bytes_stored(store_root)
          send_line({ "type" => "NEED", "sha256" => hashes.first(64) })
          message = read_line
          return unless message.is_a?(Hash) && message["type"] == "HAVE"

          Array(message["assets"]).each do |hash, size|
            next if size.nil?
            next if feed.author != @identity.master_public &&
              others_bytes + size.to_i > REPLICA_ASSET_CAP

            send_line({ "type" => "FETCH", "sha256" => hash })
            reply = read_line
            next unless reply.is_a?(Hash) && reply["type"] == "HAVE" && reply.dig("assets", hash)

            bytes = @socket.read(reply.dig("assets", hash).to_i)
            next if bytes.nil? || Canonical.digest(bytes) != hash

            Assets.put(bytes, store_root)
            others_bytes += bytes.bytesize
          end
        end
      end

      class Server
        def initialize(port:, identity:, peers:, private_hex:, store_root: Feed.root, lan: true, relay: nil,
            auto_rendezvous: false, peers_loader: nil, rendezvous_agent: nil, relay_announcer: nil)
          @port = port.to_i
          @identity = identity
          @peers = peers
          @private_hex = private_hex
          @store_root = store_root
          @lan = lan
          @relay = relay
          @auto_rendezvous = auto_rendezvous
          @peers_loader = peers_loader
          @rendezvous_agent = rendezvous_agent
          @relay_announcer = relay_announcer
          @slots = SizedQueue.new(MAX_CONNECTIONS)
          MAX_CONNECTIONS.times { @slots << true }
          @dials = Hash.new { |hash, key| hash[key] = [] }
          @dials_mutex = Mutex.new
        end

        def run
          server = TCPServer.new("0.0.0.0", @port)
          context = Tls.server_context(@private_hex)
          agent = @rendezvous_agent
          announcer = @relay_announcer
          if @auto_rendezvous
            agent ||= Net::RendezvousAgent.new(identity: @identity, peers: @peers,
              private_hex: @private_hex, store_root: @store_root, port: @port,
              peers_loader: @peers_loader)
            agent.start
            if @relay&.open?
              announcer ||= Net::RelayAnnouncer.new(port: @port)
              announcer.start
            end
          end
          beacon = LanBeacon.new(port: @port, node: @identity.master_public, private_hex: @private_hex) if @lan
          beacon&.start
          loop do
            socket = server.accept
            ip = socket.peeraddr[3] rescue "unknown"
            next unless take_slot_nonblock && under_rate?(ip)

            Thread.new(socket) do |connection|
              begin
                ssl = OpenSSL::SSL::SSLSocket.new(connection, context)
                begin
                  Timeout.timeout(CONNECT_TIMEOUT) { ssl.accept }
                rescue StandardError
                  connection.close rescue nil
                  next
                end
                # The transport authenticates nothing on this side: any
                # well-formed Ed25519 cert gets records, because records are
                # public data and every one is signature-verified by the
                # puller. Authentication lives on the dial side (pinning) and
                # in the records themselves — a server that demanded to know
                # every puller could never meet a new follower.
                begin
                  Tls.peer_key(ssl)
                rescue Error
                  ssl.close rescue nil
                  next
                end
                begin
                  peers = current_peers
                  follows = ->(pub) { pub == @identity.master_public || peers.follow?(pub) }
                  session = Session.new(socket: ssl, identity: @identity, store_root: @store_root,
                    follows: follows)
                  session.say_hello
                  session.read_hello
                  session.serve_loop(peers: peers, store_root: @store_root, relay: @relay)
                rescue StandardError
                  nil
                ensure
                  ssl.close rescue nil
                end
              ensure
                @slots << true
              end
            end
          end
        ensure
          beacon&.stop
          agent&.stop
          announcer&.stop
          server&.close rescue nil
        end

        private

        def current_peers
          @peers_loader ? @peers_loader.call : @peers
        rescue StandardError
          @peers
        end

        def take_slot_nonblock
          @slots.pop(true)
          true
        rescue ThreadError
          false
        end

        def under_rate?(ip)
          now = Time.now.to_i
          @dials_mutex.synchronize do
            window = @dials[ip].select { |at| now - at < 60 }
            if window.size >= RATE_PER_MINUTE
              @dials[ip] = window
              next false
            end
            @dials[ip] = window + [ now ]
            true
          end
        end
      end

      # LAN presence, signed: a UDP broadcast saying "a node is here" every
      # 10s, and a listener collecting others'. Same-room sync with no
      # configuration. Each announcement carries the announcer's device key,
      # a timestamp, and a signature over both — a spoofed beacon fails the
      # check and never enters the map. Replay window is 60 s.
      class LanBeacon
        BROADCAST_PORT = 7677
        INTERVAL = 10
        REPLAY_WINDOW = 60

        def initialize(port:, node:, private_hex: nil)
          @port = port
          @node = node
          @private_hex = private_hex
          @seen = {}
          @running = false
        end

        attr_reader :seen

        def start
          @running = true
          @announce = Thread.new do
            socket = UDPSocket.new
            socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
            while @running
              begin
                socket.send(JSON.generate(announcement),
                  0, "255.255.255.255", BROADCAST_PORT)
              rescue StandardError
                nil
              end
              sleep INTERVAL
            end
            socket.close rescue nil
          end
          @listen = Thread.new do
            socket = UDPSocket.new
            begin
              socket.bind("0.0.0.0", BROADCAST_PORT)
              while @running
                begin
                  data, addr = socket.recvfrom(2048)
                  node, host, port = self.class.verify_announcement(data)
                  next if node.nil? || node == @node

                  @seen[node] = { "host" => addr[3] || host, "port" => port, "at" => Time.now.to_i }
                rescue StandardError
                  nil
                end
              end
            rescue StandardError
              nil
            ensure
              socket.close rescue nil
            end
          end
          self
        end

        def stop
          @running = false
          @announce&.kill
          @listen&.kill
        end

        private

        def announcement
          at = Time.now.to_i
          payload = { "node" => @node, "port" => @port, "at" => at }
          if @private_hex
            bytes = Canonical.signing_bytes(author: @node, seq: at, prev: @port.to_s,
              kind: "beacon", body: { "port" => @port })
            payload["device"] = Keys.public_from_private(@private_hex)
            payload["sig"] = Keys.sign(@private_hex, bytes)
          end
          payload
        end

        # Returns [node, host, port] or [nil, nil, nil]. Unsigned legacy
        # announcements are ignored, not grandfathered — silence beats a
        # spoofable map.
        def self.verify_announcement(data)
          message = JSON.parse(data)
          return [ nil, nil, nil ] unless message.is_a?(Hash)

          node = message["node"].to_s
          port = message["port"].to_i
          at = message["at"].to_i
          device = message["device"].to_s
          sig = message["sig"].to_s
          return [ nil, nil, nil ] unless Keys.valid_public?(node) && port.positive? && port < 65_536
          return [ nil, nil, nil ] unless Keys.valid_public?(device)
          return [ nil, nil, nil ] if (Time.now.to_i - at).abs > REPLAY_WINDOW

          bytes = Canonical.signing_bytes(author: node, seq: at, prev: port.to_s,
            kind: "beacon", body: { "port" => port })
          return [ nil, nil, nil ] unless Keys.verify(device, sig, bytes)

          [ node, nil, port ]
        rescue JSON::ParserError, StandardError
          [ nil, nil, nil ]
        end
      end
    end
  end
end
