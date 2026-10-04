# frozen_string_literal: true

require "base64"
require "securerandom"

module RiceSpace
  module P2p
    module Net
      # A consenting TCP byte-bridge: an outbound-only node asks a reachable
      # peer to carry opaque TLS bytes to a third node. The relay opens no
      # TLS itself — it copies blobs between two sockets, each still pinned
      # end-to-end. Content-opaque, byte-capped, consent-only.
      module Relay
        SESSION_CAP = 32 * 1024 * 1024
        SESSION_LIFETIME = 600
        MAX_SESSIONS = 8

        # Serving-side registry: bridged sessions plus open-rendezvous
        # tickets. `open: true` (peer serve --relay-open) lets two strangers
        # meet by ticket; the default only bridges for callers naming a
        # followed target (peer serve --relay).
        TICKET_LIFETIME = 300
        MAX_TICKETS = 64

        class Registry
          def initialize(open: false)
            @sessions = {}
            @tickets = {}
            @open = open
            @mutex = Mutex.new
          end

          def open? = @open

          def create(one, two)
            id = SecureRandom.hex(8)
            @mutex.synchronize do
              prune
              raise Error, "too many relay sessions" if @sessions.size >= MAX_SESSIONS

              @sessions[id] = { one: one, two: two, moved: 0, until: Time.now.to_i + SESSION_LIFETIME }
            end
            id
          end

          # A waiting caller: ALLOC registers a waiter and returns its
          # secret; JOIN with the secret pairs the two control connections
          # under one session id. Single-use, 5 min expiry.
          Waiter = Struct.new(:secret, :queue)

          def alloc_waiter
            raise Error, "this relay is not open" unless @open

            secret = SecureRandom.hex(8)
            waiter = Waiter.new(secret, Queue.new)
            @mutex.synchronize do
              prune
              raise Error, "too many rendezvous tickets" if @tickets.size >= MAX_TICKETS

              @tickets[secret] = { waiter: waiter, until: Time.now.to_i + TICKET_LIFETIME }
            end
            waiter
          end

          # Block until the JOIN leg pairs this ticket (or it expires).
          # The block runs first: it watches the waiter's own connection for
          # HANGUP/close (:hungup) while waiting.
          def await_pair(secret, timeout)
            waiter = @mutex.synchronize { @tickets[secret.to_s]&.fetch(:waiter, nil) }
            return nil if waiter.nil?

            watcher = Thread.new do
              result = yield
              waiter.queue << result if result
            end
            deadline = Time.now + timeout
            loop do
              begin
                return waiter.queue.pop(true)
              rescue ThreadError
                nil
              end
              expired = @mutex.synchronize do
                entry = @tickets[secret.to_s]
                entry.nil? || Time.now.to_i > entry[:until]
              end
              if expired
                watcher.kill
                @mutex.synchronize { @tickets.delete(secret.to_s) }
                return nil
              end
              return :hungup unless watcher.alive? || waiter.queue.empty?
              break :hungup unless watcher.alive?
              sleep 0.1
              break nil if Time.now > deadline
            end
          ensure
            watcher&.kill
          end

          # The JOIN leg: consume the ticket, create the paired session, wake
          # the waiter with its session id. Returns the session id or nil.
          def pair(secret)
            session = nil
            waiter = @mutex.synchronize do
              prune
              entry = @tickets.delete(secret.to_s)
              next nil if entry.nil? || Time.now.to_i > entry[:until]

              id = SecureRandom.hex(8)
              @sessions[id] = { pair: true, moved: 0, until: Time.now.to_i + SESSION_LIFETIME,
                inbox: { entry[:waiter].secret => Queue.new, "join" => Queue.new } }
              session = id
              entry[:waiter]
            end
            return nil if waiter.nil?

            waiter.queue << { session: session }
            session
          end

          # Frame shuttle for a paired session: each leg's BYTES frames land
          # in the other leg's inbox; take() blocks for the next one.
          def shuttle(id, leg, blob)
            queues = @mutex.synchronize { @sessions[id.to_s]&.fetch(:inbox, nil) }
            return nil if queues.nil?

            other = queues.keys.find { |key| key != leg }
            return nil if other.nil? || queues[other].nil?

            account(id, blob.bytesize)
            queues[other] << blob
            true
          rescue Error
            nil
          end

          def take(id, leg, timeout = 15)
            queue = @mutex.synchronize { @sessions[id.to_s]&.dig(:inbox, leg) }
            return nil if queue.nil?

            deadline = Time.now + timeout
            loop do
              begin
                return queue.pop(true)
              rescue ThreadError
                nil
              end
              return nil if fetch(id).nil?
              return nil if Time.now > deadline

              sleep 0.05
            end
          end

          def fetch(id)
            @mutex.synchronize do
              entry = @sessions[id.to_s]
              return nil if entry.nil? || Time.now.to_i > entry[:until]

              entry
            end
          end

          def account(id, bytes)
            @mutex.synchronize do
              entry = @sessions[id.to_s]
              raise Error, "relay session is over its byte cap" if entry.nil?

              entry[:moved] += bytes.to_i
              if entry[:moved] > SESSION_CAP
                @sessions.delete(id.to_s)
                raise Error, "relay session is over its byte cap"
              end
            end
          end

          def drop(id)
            @mutex.synchronize { @sessions.delete(id.to_s) }
          end

          private

          def prune
            now = Time.now.to_i
            @sessions.delete_if { |_, entry| now > entry[:until] }
            @tickets.delete_if { |_, entry| now > entry[:until] }
          end
        end

        # Dial-side: open a bridged sync session through a relay to a target
        # feed. The control connection is TLS to the relay (pinned); the
        # bridged stream is TLS to the *target* (pinned to its live device,
        # resolved from the feed, or its master) — the relay sees ciphertext.
        # Returns an open Sync::Session over the bridge.
        def self.dial(relay_host, relay_port, identity:, peers:, private_hex:,
            target_feed:, relay_pin:, target_pin: nil, store_root: Feed.root)
          control = Sync::Session.connect(relay_host, relay_port, identity: identity,
            peers: peers, private_hex: private_hex, expected_key: relay_pin,
            store_root: store_root)
          control.send_line({ "type" => "BRIDGE", "to" => target_feed.to_s })
          reply = control.read_line
          unless reply.is_a?(Hash) && reply["type"] == "BRIDGED" && reply["session"].is_a?(String)
            control.close
            raise Error, "the relay has no route to that peer"
          end
          # The endpoint slot's device (provisional first-contact pin) wins
          # when given: the caller has no feed history yet, and the target
          # serves its device cert. Records still verify against the master.
          pin = target_pin || dial_pin_for(target_feed, store_root)
          # OpenSSL only wraps real IOs, so the bridged stream is a real
          # UNIX socketpair with a pump thread behind it: socketpair <->
          # BYTES frames. TLS terminates end-to-end; the thread sees bytes.
          local, peer = Socket.pair(:UNIX, :STREAM, 0)
          pump = Pump.new(session: control, id: reply["session"], io: peer)
          thread = Thread.new { pump.run }
          begin
            Sync::Session.connect_io(local, target_feed.to_s, identity: identity, peers: peers,
              private_hex: private_hex, expected_key: pin, store_root: store_root)
          rescue StandardError
            thread.kill
            local.close rescue nil
            raise
          end
        rescue Error
          raise
        rescue StandardError => error
          raise Error, "relay dial failed (#{error.class})"
        end

        # Rendezvous dial: ALLOC a ticket at an open relay, or JOIN one.
        # Returns [control_session, session_id] after ALLOC+PAIRED, or the
        # paired session id after JOIN. The caller wraps its end in TLS via
        # the socketpair Pump, exactly like the friend bridge.
        def self.alloc(relay_host, relay_port, identity:, peers:, private_hex:,
            relay_pin:, store_root: Feed.root)
          control = Sync::Session.connect(relay_host, relay_port, identity: identity,
            peers: peers, private_hex: private_hex, expected_key: relay_pin,
            store_root: store_root)
          control.send_line({ "type" => "ALLOC" })
          reply = control.read_line
          unless reply.is_a?(Hash) && reply["type"] == "ALLOCATED" && reply["secret"].is_a?(String)
            control.close
            raise Error, "the relay refused the rendezvous"
          end
          [ control, reply["secret"] ]
        end

        # Wait for the stranger to JOIN (PAIRED), then open the end-to-end
        # TLS session over the paired frames — server role, while the joiner
        # connects. Returns the Sync session.
        def self.await_peer(control, secret, identity:, peers:, private_hex:,
            target_feed:, target_pin:, store_root: Feed.root)
          reply = control.read_line(timeout: TICKET_LIFETIME)
          unless reply.is_a?(Hash) && reply["type"] == "PAIRED" && reply["session"].is_a?(String)
            control.close
            raise Error, "nobody joined the rendezvous"
          end
          pin = target_pin || dial_pin_for(target_feed, store_root)
          local, peer = Socket.pair(:UNIX, :STREAM, 0)
          pump = FramedPump.new(session: control, id: reply["session"], io: peer)
          thread = Thread.new { pump.run }
          begin
            Sync::Session.accept_io(local, target_feed.to_s, identity: identity, peers: peers,
              private_hex: private_hex, expected_key: pin, store_root: store_root)
          rescue StandardError
            thread.kill
            local.close rescue nil
            raise
          end
        end

        # JOIN a ticket somebody signalled: returns the end-to-end Sync
        # session over the paired frames. relay_pin :none means the relay is
        # a stranger — the control leg is explicitly unpinned, and all trust
        # rides the end-to-end TLS plus the ticket secret.
        def self.join(relay_host, relay_port, secret, identity:, peers:, private_hex:,
            target_feed:, target_pin:, relay_pin:, store_root: Feed.root)
          control = Sync::Session.connect(relay_host, relay_port, identity: identity,
            peers: peers, private_hex: private_hex, expected_key: relay_pin,
            store_root: store_root)
          control.send_line({ "type" => "JOIN", "secret" => secret })
          reply = control.read_line
          unless reply.is_a?(Hash) && reply["type"] == "JOINED" && reply["session"].is_a?(String)
            control.close
            raise Error, "the relay has no such rendezvous"
          end
          stream_over(control, reply["session"], identity: identity, peers: peers,
            private_hex: private_hex, target_feed: target_feed, target_pin: target_pin,
            leg: "join", store_root: store_root)
        end

        def self.stream_over(control, session_id, identity:, peers:, private_hex:,
            target_feed:, target_pin:, leg:, store_root:)
          pin = target_pin || dial_pin_for(target_feed, store_root)
          local, peer = Socket.pair(:UNIX, :STREAM, 0)
          pump = FramedPump.new(session: control, id: session_id, io: peer)
          thread = Thread.new { pump.run }
          begin
            Sync::Session.connect_io(local, target_feed.to_s, identity: identity, peers: peers,
              private_hex: private_hex, expected_key: pin, store_root: store_root)
          rescue StandardError
            thread.kill
            local.close rescue nil
            raise
          end
        end
        private_class_method :stream_over

        # Pump between a socketpair and BYTES frames on a paired control
        # connection: the dial-side mirror of the relay's pump_paired.
        class FramedPump
          CHUNK = 16_384

          def initialize(session:, id:, io:)
            @session = session
            @id = id
            @io = io
            @mutex = Mutex.new
          end

          def run
            reader = Thread.new { run_reader }
            run_writer
            reader.kill
          rescue StandardError
            nil
          ensure
            reader&.kill
            @session.send_line({ "type" => "HANGUP", "session" => @id }) rescue nil
            @io.close rescue nil
          end

          private

          def run_writer
            loop do
              ready, = IO.select([ @io ], nil, nil, 30)
              break if ready.nil?

              chunk = begin
                @io.read_nonblock(CHUNK)
              rescue IO::WaitReadable
                next
              rescue StandardError
                break
              end
              break if chunk.nil? || chunk.empty?

              @mutex.synchronize do
                @session.send_line({ "type" => "BYTES", "session" => @id,
                  "blob" => Base64.strict_encode64(chunk.b) })
              end
            end
          end

          def run_reader
            loop do
              reply = @session.read_line
              break unless reply.is_a?(Hash) && reply["session"].to_s == @id
              break if reply["type"] == "BYE" || reply["type"] == "NOROUTE"

              next unless reply["type"] == "BYTES"

              down = begin
                Base64.strict_decode64(reply["blob"].to_s)
              rescue ArgumentError
                break
              end
              begin
                @io.write(down) unless down.empty?
              rescue StandardError
                break
              end
            end
          rescue StandardError
            nil
          end
        end

        # The pin for the bridged TLS leg: the feed's live device, else its
        # master. Mirrors the direct-dial pinning — the bridge changes the
        # path, never the authentication.
        def self.dial_pin_for(feed_pub, store_root)
          feed = Feed.new(feed_pub.to_s, root: store_root)
          return feed_pub.to_s if feed.records.empty?

          result = feed.verify
          return feed_pub.to_s unless result.ok?

          live = result.state["devices"].reject { |_key, device| device["revoked"] }.keys.first
          live.nil? || live == feed_pub.to_s ? feed_pub.to_s : live
        rescue Error
          feed_pub.to_s
        end
        private_class_method :dial_pin_for

        # Pump: full-duplex shuttle between a real socket (OpenSSL's end)
        # and BYTES frames (the relay's end). The write loop frames socket
        # bytes up; a reader thread writes the relay's bytes back down.
        # Request/response framing would deadlock the TLS handshake (both
        # sides waiting for the other's flight), so the two directions are
        # independent — the relay's pump_bridge answers every frame.
        class Pump
          CHUNK = 16_384

          def initialize(session:, id:, io:)
            @session = session
            @id = id
            @io = io
            @mutex = Mutex.new
          end

          def run
            reader = Thread.new { run_reader }
            run_writer
            reader.kill
          rescue StandardError
            nil
          ensure
            reader&.kill
            @session.send_line({ "type" => "HANGUP", "session" => @id }) rescue nil
            @io.close rescue nil
          end

          private

          def run_writer
            loop do
              ready, = IO.select([ @io ], nil, nil, 30)
              break if ready.nil?

              chunk = begin
                @io.read_nonblock(CHUNK)
              rescue IO::WaitReadable
                next
              rescue StandardError
                break
              end
              break if chunk.nil? || chunk.empty?

              @mutex.synchronize do
                @session.send_line({ "type" => "BYTES", "session" => @id,
                  "blob" => Base64.strict_encode64(chunk.b) })
              end
            end
          end

          def run_reader
            loop do
              reply = @session.read_line
              break unless reply.is_a?(Hash) && reply["session"].to_s == @id
              break if reply["type"] == "BYE" || reply["type"] == "NOROUTE"

              next unless reply["type"] == "BYTES"

              down = begin
                Base64.strict_decode64(reply["blob"].to_s)
              rescue ArgumentError
                break
              end
              begin
                @io.write(down) unless down.empty?
              rescue StandardError
                break
              end
            end
          rescue StandardError
            nil
          end
        end
      end
    end
  end
end
