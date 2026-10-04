# frozen_string_literal: true

module RiceSpace
  module P2p
    module Net
      # Outbound rendezvous for every followed account. Each pair's ticket is
      # published in a distinct BEP44 salt; the relay sees no feed contents.
      class RendezvousAgent
        BASE_REPUBLISH_INTERVAL = 3600
        TICKET_EXPIRY_SKEW = 5

        def initialize(identity:, peers:, private_hex:, store_root: Feed.root, port: 7676,
            relay_source: nil, ticket_publisher: nil, peers_loader: nil, retry_interval: 30,
            follow_poll_interval: 5, dht_factory: -> { Dht.new })
          @identity = identity
          @peers = peers
          @private_hex = private_hex
          @store_root = store_root
          @port = port.to_i
          @relay_source = relay_source || method(:discover_relays)
          @owns_publisher = ticket_publisher.nil?
          @ticket_publisher = ticket_publisher || method(:publish_ticket)
          @peers_loader = peers_loader
          @retry_interval = retry_interval
          @follow_poll_interval = follow_poll_interval
          @dht_factory = dht_factory
          @state_mutex = Mutex.new
          @state_cv = ConditionVariable.new
          @running = false
          @controls = []
          @sessions = []
          @threads = []
          @workers = {}
        end

        def start
          @state_mutex.synchronize do
            return self if @running

            @running = true
          end
          refresh_follows
          @state_mutex.synchronize do
            @threads << Thread.new { monitor_follows } if @peers_loader
            @threads << Thread.new { republish_base_slot } if @owns_publisher
          end
          self
        end

        def stop
          controls, sessions, threads = @state_mutex.synchronize do
            @running = false
            @state_cv.broadcast
            [ @controls.dup, @sessions.dup, @threads.dup ]
          end
          controls.each { |control| control.close rescue nil }
          sessions.each { |session| session.close rescue nil }
          threads.each { |thread| thread.join(2) }
          self
        end

        private

        def running?
          @state_mutex.synchronize { @running }
        end

        def wait_or_stop(seconds)
          @state_mutex.synchronize { @state_cv.wait(@state_mutex, seconds) if @running }
        end

        def monitor_follows
          while running?
            refresh_follows
            wait_or_stop(@follow_poll_interval)
          end
        end

        def refresh_follows
          current = @peers_loader ? @peers_loader.call : @peers
          @state_mutex.synchronize do
            return unless @running

            @peers = current
            current.follows.each_key do |pub|
              next if @workers.key?(pub)

              @workers[pub] = Thread.new { serve_follow(pub) }
              @threads << @workers[pub]
            end
          end
        rescue StandardError
          nil
        end

        def serve_follow(pub)
          while running?
            control = nil
            session = nil
            begin
              connection = allocate_ticket
              unless connection
                wait_or_stop(@retry_interval)
                next
              end
              control, secret, relay_addr = connection
              unless track(@controls, control)
                control.close rescue nil
                break
              end
              ticket = { "relay" => relay_addr, "secret" => secret, "peer" => pub,
                "expires" => Time.now.to_i + Relay::TICKET_LIFETIME - TICKET_EXPIRY_SKEW }
              raise Error, "could not publish rendezvous ticket" unless @ticket_publisher.call(pub, ticket)

              session = Relay.await_peer(control, secret, identity: @identity, peers: @peers,
                private_hex: @private_hex, target_feed: pub, target_pin: device_pin(pub),
                store_root: @store_root)
              @ticket_publisher.call(pub, nil)
              unless track(@sessions, session)
                session.close rescue nil
                break
              end
              session.serve_loop(peers: @peers, store_root: @store_root)
            rescue StandardError
              nil
            ensure
              untrack(@sessions, session) if session
              untrack(@controls, control) if control
              session&.close rescue nil
              control&.close rescue nil
            end
            wait_or_stop(@retry_interval) if running?
          end
        end

        def allocate_ticket
          candidates = Array(@relay_source.call).filter_map do |entry|
            entry.is_a?(Hash) ? entry["addr"] : entry
          end.uniq
          candidates.each do |addr|
            host, port = addr.to_s.split(":", 2)
            next if host.to_s.empty? || port.to_s.empty?

            begin
              return [ *Relay.alloc(host, Integer(port, 10), identity: @identity,
                peers: @peers, private_hex: @private_hex, relay_pin: :none,
                store_root: @store_root), addr.to_s ]
            rescue Error, ArgumentError
              next
            end
          end
          nil
        rescue StandardError
          nil
        end

        def device_pin(pub)
          key = @peers.endpoint_for(pub)["device"]
          Keys.valid_public?(key.to_s) ? key : nil
        end

        def track(collection, object)
          @state_mutex.synchronize do
            return false unless @running

            collection << object
            true
          end
        end

        def untrack(collection, object)
          @state_mutex.synchronize { collection.delete(object) }
        end

        def discover_relays
          dht = @dht_factory.call
          begin
            dht.bootstrap
            Relays.discover(dht: dht).map { |relay| relay["addr"] }
          rescue Error
            Relays.list.map { |relay| relay["addr"] }
          ensure
            dht.close rescue nil
          end
        end

        def republish_base_slot
          while running?
            dht = @dht_factory.call
            begin
              dht.bootstrap
              ensure_base_slot(dht)
            rescue Error
              nil
            ensure
              dht.close rescue nil
            end
            wait_or_stop(BASE_REPUBLISH_INTERVAL)
          end
        end

        def publish_ticket(pub, ticket)
          dht = @dht_factory.call
          begin
            dht.bootstrap
            ensure_base_slot(dht)
            record = Endpoint.build(node: @identity.master_public, device: @identity.device_public,
              addrs: [], rv: ticket ? [ ticket["relay"] ] : [], ticket: ticket,
              sign_with: @private_hex)
            accepted = dht.publish(@identity.device_public, @private_hex,
              Endpoint.pack(record), salt: Dht.rendezvous_salt(pub))
            accepted.positive?
          rescue Error
            false
          ensure
            dht.close rescue nil
          end
        end

        def ensure_base_slot(dht)
          raw = dht.fetch(@identity.device_public)
          current = if raw
            begin
              chain = Feed.new(@identity.master_public, root: @store_root).verify
              Endpoint.verify(Endpoint.unpack(raw[:v]), chain: chain)
            rescue Error
              nil
            end
          end
          if current && current["exp"].to_i - Time.now.to_i > BASE_REPUBLISH_INTERVAL
            return true
          end

          record = Endpoint.build(node: @identity.master_public, device: @identity.device_public,
            addrs: current ? current["addrs"] : [], relay: current ? current["relay"] : [],
            rv: current ? current["rv"] : [], nat: current ? current["nat"] : "unknown",
            sign_with: @private_hex)
          dht.publish(@identity.device_public, @private_hex, Endpoint.pack(record)).positive?
        end
      end

      # Open volunteer listeners publish their TCP service on the well-known
      # BEP5 swarm and renew the short-lived announcement while serving.
      class RelayAnnouncer
        DEFAULT_INTERVAL = 15 * 60

        def initialize(port:, dht_factory: -> { Dht.new }, interval: DEFAULT_INTERVAL)
          @port = port.to_i
          @dht_factory = dht_factory
          @interval = interval
          @mutex = Mutex.new
          @condition = ConditionVariable.new
          @running = false
          @current_dht = nil
        end

        def start
          @mutex.synchronize { @running = true }
          @thread = Thread.new { announce_loop }
          self
        end

        def stop
          dht, thread = @mutex.synchronize do
            @running = false
            @condition.broadcast
            [ @current_dht, @thread ]
          end
          dht&.close rescue nil
          thread&.join(15)
          self
        end

        private

        def announce_loop
          loop do
            break unless running?

            dht = @dht_factory.call
            @mutex.synchronize { @current_dht = dht }
            begin
              dht.bootstrap
              dht.announce_peer(port: @port)
            rescue Error
              nil
            ensure
              @mutex.synchronize { @current_dht = nil }
              dht.close rescue nil
            end
            @mutex.synchronize do
              break unless @running

              @condition.wait(@mutex, @interval)
            end
          end
        rescue StandardError
          retry if running?
        end

        def running?
          @mutex.synchronize { @running }
        end
      end
    end
  end
end
