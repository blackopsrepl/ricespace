# frozen_string_literal: true

require "json"
require "pathname"

module RiceSpace
  module P2p
    module Net
      # Discovery state: the DHT routing table between runs, our published
      # slot's age, and per-follow resolution. One file, 0600, beside the
      # identity — losing it only costs a re-bootstrap, never identity.
      class Discovery
        FILENAME = "dht.json"
        REPUBLISH_INTERVAL = 3600

        def initialize(path:, table: [], published_at: nil)
          @path = path
          @table = table
          @published_at = published_at
        end

        attr_reader :table, :published_at

        def self.path(config_dir = Config::DIRECTORY)
          Pathname.new(config_dir.to_s).join(FILENAME)
        end

        def self.load(config_dir = Config::DIRECTORY)
          file = path(config_dir)
          if file.file?
            begin
              data = JSON.parse(file.read)
              return new(path: file, table: Array(data["table"]),
                published_at: data["published_at"])
            rescue JSON::ParserError
              nil
            end
          end
          new(path: file)
        end

        def save
          @path.dirname.mkpath
          temp = Pathname.new("#{@path}.new")
          temp.write(JSON.pretty_generate({ "table" => @table.last(128),
            "published_at" => @published_at }) + "\n")
          temp.chmod(0o600)
          temp.rename(@path)
          self
        end

        def note_table(entries)
          @table = ((@table + Array(entries)).uniq(&:first)).last(128)
          save
        end

        def note_published
          @published_at = Time.now.to_i
          save
        end

        def due_to_republish?
          @published_at.nil? || Time.now.to_i - @published_at >= REPUBLISH_INTERVAL
        end

        # Resolve one follow to dial candidates: manual addrs first (they
        # always win), then a verified DHT slot, each tagged with its pin.
        # own_pub (our master key) enables the rendezvous rung: it fires when
        # the follow's slot carries a ticket naming us.
        # Returns [{addr:, pin:, via:}] — via is :manual, :dht, :relay or
        # :rendezvous.
        def self.resolve(peers, pub, dht: nil, store_root: Feed.root, own_pub: nil)
          out = []
          peers.addrs_for(pub).each do |addr|
            out << { addr: addr, pin: nil, via: :manual }
          end
          return out if dht.nil?

          slot = fetch_slot(dht, pub, store_root, device_hint: peers.endpoint_for(pub)["device"])
          return out if slot.nil?

          slot["addrs"].each do |addr|
            next if Endpoint.lan_only?(addr) && !local_net?(peers.addrs_for(pub))

            out << { addr: addr, pin: slot["device"], via: :dht }
          end
          # Open rendezvous: the follow waits at these relays with a ticket
          # naming us. The relay address is not pinned (stranger relay) —
          # both TLS legs pin end-to-end instead.
          tickets = Array(slot["tickets"])
          tickets << slot["ticket"] unless slot["ticket"].nil?
          pair_slot = fetch_pair_ticket(dht, pub, slot, own_pub, store_root) unless own_pub.nil?
          tickets << pair_slot["ticket"] if pair_slot.is_a?(Hash) && pair_slot["ticket"].is_a?(Hash)
          tickets.uniq.each do |ticket|
            next unless ticket.is_a?(Hash) && !own_pub.nil? &&
              ticket["peer"].to_s.downcase == own_pub.to_s.downcase &&
              ticket["relay"].is_a?(String) &&
              (ticket["expires"].nil? || ticket["expires"].to_i > Time.now.to_i)

            out << { addr: ticket["relay"], pin: slot["device"], via: :rendezvous,
              ticket: ticket, relay_feed: nil }
          end
          Array(slot["relay"]).each do |addr|
            # The relay is pinned by its own key, which must be a follow
            # whose address this is — an unpinnable relay is no rung at all.
            bridge = peers.follows.find do |_key, entry|
              Array(entry.is_a?(Hash) ? entry["addrs"] : []).include?(addr)
            end
            next if bridge.nil?

            out << { addr: addr, pin: slot["device"], via: :relay,
              relay_for: pub, relay_feed: bridge.first }
          end
          out
        end

        def self.fetch_slot(dht, pub, store_root, device_hint: nil)
          devices = live_devices(pub, store_root)
          devices << device_hint.to_s if Keys.valid_public?(device_hint.to_s)
          devices.uniq!
          return nil if devices.empty? && !followed_without_history?(pub, store_root)

          devices.each do |device|
            raw = dht.fetch(device)
            next if raw.nil?

            begin
              record = Endpoint.verify(Endpoint.unpack(raw[:v]),
                chain: feed_chain(pub, store_root))
              return record if record["node"].to_s.downcase == pub.to_s.downcase
            rescue Error
              next
            end
          end
          # First contact: no history, so no device list. Try the feed key
          # itself as the slot key — a device-less publisher's only slot.
          # Verification runs signature-only; the caller pins provisionally.
          begin
            raw = dht.fetch(pub.to_s)
          rescue Error
            return nil
          end
          return nil if raw.nil?

          begin
            record = Endpoint.verify(Endpoint.unpack(raw[:v]), chain: nil)
            return record if record["node"].to_s.downcase == pub.to_s.downcase
          rescue Error
            nil
          end
          nil
        end
        private_class_method :fetch_slot

        def self.fetch_pair_ticket(dht, pub, slot, own_pub, store_root)
          return nil unless Keys.valid_public?(own_pub.to_s)

          raw = dht.fetch(slot["device"], salt: Dht.rendezvous_salt(own_pub))
          return nil if raw.nil?

          record = Endpoint.verify(Endpoint.unpack(raw[:v]), chain: feed_chain(pub, store_root))
          record if record["node"].to_s.downcase == pub.to_s.downcase
        rescue Error
          nil
        end
        private_class_method :fetch_pair_ticket

        def self.feed_chain(pub, store_root)
          feed = Feed.new(pub.to_s, root: store_root)
          return nil if feed.records.empty?

          feed.verify
        end
        private_class_method :feed_chain

        def self.live_devices(pub, store_root)
          chain = feed_chain(pub, store_root)
          return [] if chain.nil? || !chain.ok?

          devices = chain.state["devices"].reject { |_key, device| device["revoked"] }.keys
          owner = chain.state["owner"].to_s
          ([ owner ] + devices).uniq.select { |key| Keys.valid_public?(key) }
        end
        private_class_method :live_devices

        def self.followed_without_history?(pub, store_root)
          Feed.new(pub.to_s, root: store_root).records.empty?
        end
        private_class_method :followed_without_history?

        def self.local_net?(addrs)
          Array(addrs).any? { |addr| Endpoint.lan_only?(addr.to_s) }
        end
        private_class_method :local_net?
      end
    end
  end
end
