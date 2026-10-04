# frozen_string_literal: true

require "digest/sha1"
require "socket"
require "timeout"

module RiceSpace
  module P2p
    module Net
      # A Mainline DHT node: BEP5 routing plus BEP44 mutable slots, stdlib
      # only, over one UDPSocket. Node ids are random per process — routing
      # position, never identity.
      class Dht
        ROUTERS = [
          [ "dht.transmissionbt.com", 6881 ],
          [ "router.utorrent.com", 6881 ],
          [ "dht.libtorrent.org", 6881 ]
        ].freeze

        QUERY_TIMEOUT = 4
        MAX_INFLIGHT = 64
        TABLE_CAP = 128
        PUT_REPLICAS = 8
        SALT = "ricespace-ep-v1"

        def initialize(socket: nil, node_id: nil)
          @socket = socket
          @owned_socket = socket.nil?
          @node_id = (node_id || Random.bytes(20)).b
          @table = []
          @table_mutex = Mutex.new
          @inflight = 0
          @inflight_mutex = Mutex.new
        end

        # The BEP44 target for an Ed25519 device key: SHA1 of the raw key
        # bytes, or of key bytes + salt. Our device keys are 32 bytes of hex.
        def self.target_for(device_hex, salt: nil)
          raw = [ device_hex.to_s.downcase ].pack("H*")
          salt.nil? || salt.empty? ? Digest::SHA1.hexdigest(raw) : Digest::SHA1.hexdigest(raw + salt.to_s.b)
        end

        # The exact bytes a BEP44 mutable signature covers: the bencoded
        # "salt" pair (when present), then "seq", then "v" — i.e. exactly
        # "4:salt6:foobar3:seqi1e1:v12:Hello World!" for the spec's vector.
        # Our v rides as a byte string (already-bencoded endpoint JSON).
        def self.signed_bytes(seq:, v:, salt: nil)
          payload = (v.is_a?(String) ? v.b : Bencode.encode(v).b)
          body = +""
          unless salt.nil? || salt.empty?
            body << Bencode.encode("salt") << Bencode.encode(salt.to_s.b)
          end
          body << Bencode.encode("seq") << Bencode.encode(seq.to_i)
          body << Bencode.encode("v") << "#{payload.bytesize}:#{payload}"
          body
        end

        # First contact: ping routers in order, walk closer to our own id.
        # Returns how many routers answered. Raises only when none did.
        def bootstrap(routers: ROUTERS)
          answered = routers.count do |host, port|
            begin
              query({ "t" => txid, "y" => "q", "q" => "ping",
                "a" => { "id" => @node_id } }, host, port)
              true
            rescue Error
              false
            end
          end
          raise Error, "no discovery contact — add an address manually or wait for routers" if answered.zero?

          walk_home
          answered
        end

        # Fetch the newest mutable slot for a device key. Returns
        # {seq:, v:} or nil. Majority over the closest responders: the highest
        # seq seen at least twice wins; a lone slot is returned as-is.
        def fetch(device_hex, salt: SALT)
          target = self.class.target_for(device_hex, salt: salt)
          nodes = closest_to(target, PUT_REPLICAS)
          seen = []
          nodes.each do |host, port|
            begin
              reply = query({ "t" => txid, "y" => "q", "q" => "get",
                "a" => { "id" => @node_id, "target" => [ target ].pack("H*") } }, host, port)
              inner = reply["r"]
              next unless inner.is_a?(Hash) && inner["v"]

              seen << { seq: inner["seq"].to_i, v: inner["v"].b, token: inner["token"] }
            rescue Error
              next
            end
          end
          return nil if seen.empty?

          best = seen.max_by { |entry| entry[:seq] }
          return best if seen.count { |entry| entry[:seq] == best[:seq] } >= 2 || seen.size == 1

          best
        end

        # Publish a mutable slot: get tokens from the closest nodes, put to
        # the first PUT_REPLICAS that grant one. Returns how many accepted.
        def publish(device_hex, private_hex, v, salt: SALT)
          target = self.class.target_for(device_hex, salt: salt)
          seq = Time.now.to_i
          sig_raw = Keys.sign(private_hex, self.class.signed_bytes(seq: seq, v: v, salt: salt))
          k_raw = [ device_hex.to_s.downcase ].pack("H*")
          accepted = 0
          closest_to(target, PUT_REPLICAS).each do |host, port|
            begin
              fetched = query({ "t" => txid, "y" => "q", "q" => "get",
                "a" => { "id" => @node_id, "target" => [ target ].pack("H*") } }, host, port)
              token = fetched.dig("r", "token")
              next if token.nil?

              query({ "t" => txid, "y" => "q", "q" => "put",
                "a" => { "id" => @node_id, "token" => token, "k" => k_raw,
                  "salt" => salt.to_s.b, "seq" => seq,
                  "sig" => [ sig_raw ].pack("H*"), "v" => v.b } }, host, port)
              accepted += 1
            rescue Error
              next
            end
          end
          accepted
        end

        def close
          @socket&.close if @owned_socket
        rescue StandardError
          nil
        end

        private

        def socket
          @socket ||= UDPSocket.new
        end

        def txid
          Random.bytes(2)
        end

        def take_inflight
          @inflight_mutex.synchronize do
            raise Error, "too many in-flight DHT queries" if @inflight >= MAX_INFLIGHT

            @inflight += 1
          end
        end

        def drop_inflight
          @inflight_mutex.synchronize { @inflight -= 1 }
        end

        # One KRPC round trip. Retries nothing — the caller iterates nodes,
        # which is the DHT's own retry policy.
        def query(message, host, port)
          take_inflight
          wire = Bencode.encode(message)
          socket.send(wire, 0, host.to_s, port.to_i)
          ready, = IO.select([ socket ], nil, nil, QUERY_TIMEOUT)
          raise Error, "DHT query to #{host}:#{port} timed out" if ready.nil?

          data, = socket.recvfrom(4096)
          reply = Bencode.decode(data)
          raise Error, "DHT error #{reply["e"]&.first}" if reply["y"] == "e"
          raise Error, "not a DHT reply" unless reply["y"] == "r"

          note_nodes(reply.dig("r", "nodes"))
          reply
        rescue IOError, SystemCallError, SocketError => error
          raise Error, "DHT query to #{host}:#{port} failed (#{error.class})"
        ensure
          drop_inflight
        end

        def note_nodes(compact)
          return if compact.nil?

          raw = compact.b
          offset = 0
          found = []
          while offset + 26 <= raw.bytesize
            id = raw.byteslice(offset, 20)
            ip = raw.byteslice(offset + 20, 4).unpack1("N")
            port = raw.byteslice(offset + 24, 2).unpack1("n")
            host = [ 24, 16, 8, 0 ].map { |shift| (ip >> shift) & 255 }.join(".")
            found << [ id, host, port ]
            offset += 26
          end
          @table_mutex.synchronize do
            found.each do |entry|
              @table.delete(entry)
              @table << entry
            end
            @table = @table.last(TABLE_CAP)
          end
        end

        def distance(id_bytes, target_hex)
          target = [ target_hex ].pack("H*").bytes
          mine = id_bytes.bytes
          mine.zip(target).map { |a, b| a ^ b }.pack("C*")
        end

        def closest_to(target_hex, count)
          mine = @table_mutex.synchronize { @table.dup }
          mine.sort_by { |id, _, _| distance(id, target_hex) }.first(count).map { |_, h, p| [ h, p ] }
        end

        def walk_home
          home = @node_id.unpack1("H*")
          3.times do
            nodes = closest_to(home, 8)
            break if nodes.empty?

            nodes.each do |host, port|
              begin
                query({ "t" => txid, "y" => "q", "q" => "find_node",
                  "a" => { "id" => @node_id, "target" => @node_id } }, host, port)
              rescue Error
                next
              end
            end
          end
        end
      end
    end
  end
end
