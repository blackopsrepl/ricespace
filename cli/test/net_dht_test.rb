# frozen_string_literal: true

require "minitest/autorun"
require "socket"
require "ipaddr"
require "tmpdir"
require_relative "../lib/ricespace"

class NetDhtTest < Minitest::Test
  def test_rendezvous_salt_is_stable_scoped_and_bep44_bounded
    first = RiceSpace::P2p::Keys.generate[:public_hex]
    second = RiceSpace::P2p::Keys.generate[:public_hex]

    salt = RiceSpace::P2p::Net::Dht.rendezvous_salt(first)

    assert_equal salt, RiceSpace::P2p::Net::Dht.rendezvous_salt(first)
    refute_equal salt, RiceSpace::P2p::Net::Dht.rendezvous_salt(second)
    assert_operator salt.bytesize, :<=, 64
    assert_raises(RiceSpace::P2p::Error) { RiceSpace::P2p::Net::Dht.rendezvous_salt("bad") }
  end

  def test_mutable_slot_republishes_with_a_strictly_newer_sequence
    with_dht do |dht, server, requests|
      dht.bootstrap(routers: [ [ "127.0.0.1", server.addr[1] ] ])
      drain(requests)
      key = RiceSpace::P2p::Keys.generate

      assert_equal 1, dht.publish(key[:public_hex], key[:private_hex], "first")
      first_sequence = drain(requests).find { |request| request["q"] == "put" }.dig("a", "seq")
      assert_equal 1, dht.publish(key[:public_hex], key[:private_hex], "second")
      second_sequence = drain(requests).find { |request| request["q"] == "put" }.dig("a", "seq")

      assert_operator second_sequence, :>, first_sequence
    end
  end

  def test_finds_open_relays_from_mainline_get_peers
    with_dht do |dht, server, requests|
      accepted = dht.bootstrap(routers: [ [ "127.0.0.1", server.addr[1] ] ])
      drain(requests)
      assert_equal 1, accepted

      relays = dht.find_peers

      assert_equal [ "203.0.113.19:7670" ], relays
      query = requests.pop
      assert_equal "get_peers", query.dig("q")
      assert_equal RiceSpace::P2p::Net::Dht::RELAY_TOPIC, query.dig("a", "info_hash")
    end
  end

  def test_find_peers_queries_nodes_returned_by_get_peers
    first = UDPSocket.new
    second = UDPSocket.new
    first.bind("127.0.0.1", 0)
    second.bind("127.0.0.1", 0)
    first_id = "a" * 20
    second_id = "z" * 20
    requests = Queue.new
    nodes = [ first, second ].each_with_index.map do |socket, index|
      id = index.zero? ? first_id : second_id
      Thread.new do
        loop do
          packet, peer = socket.recvfrom(4096)
          request = RiceSpace::P2p::Net::Bencode.decode(packet)
          requests << [ index, request ]
          response = { "id" => id }
          if request["q"] == "ping"
            response["nodes"] = compact_node(id, socket)
          elsif request["q"] == "get_peers"
            if index.zero?
              response["nodes"] = compact_node(second_id, second)
            else
              response["values"] = [ "\xcb\x00\x71\x13\x1d\xf6".b ]
            end
          end
          socket.send(RiceSpace::P2p::Net::Bencode.encode(
            { "t" => request["t"], "y" => "r", "r" => response }), 0, peer[3], peer[1])
        end
      rescue IOError, Errno::EBADF
        nil
      end
    end
    dht = RiceSpace::P2p::Net::Dht.new
    dht.bootstrap(routers: [ [ "127.0.0.1", first.addr[1] ] ])

    assert_equal [ "203.0.113.19:7670" ], dht.find_peers
    assert_equal [ 0, 1 ], drain(requests).select { |_index, request| request["q"] == "get_peers" }
      .map(&:first).sort
  ensure
    dht&.close
    [ first, second ].compact.each(&:close)
    nodes&.each { |node| node.kill; node.join }
  end

  def test_announces_relay_listener_with_a_fresh_mainline_token
    with_dht do |dht, server, requests|
      dht.bootstrap(routers: [ [ "127.0.0.1", server.addr[1] ] ])
      drain(requests)

      assert_equal 1, dht.announce_peer(port: 7676)

      lookup = requests.pop
      announcement = requests.pop
      assert_equal "get_peers", lookup["q"]
      assert_equal "announce_peer", announcement["q"]
      assert_equal RiceSpace::P2p::Net::Dht::RELAY_TOPIC,
        announcement.dig("a", "info_hash")
      assert_equal 7676, announcement.dig("a", "port")
      assert_equal "fresh-token", announcement.dig("a", "token")
    end
  end

  def test_find_peers_ignores_malformed_compact_values
    with_dht(values: [ "short", "\x7f\x00\x00\x01\x1d\xf6".b ]) do |dht, server, _requests|
      dht.bootstrap(routers: [ [ "127.0.0.1", server.addr[1] ] ])

      assert_equal [ "127.0.0.1:7670" ], dht.find_peers
    end
  end

  def test_relay_directory_merges_configured_and_public_dht_volunteers
    dht = Object.new
    dht.define_singleton_method(:find_peers) do
      [ "8.8.8.8:7676", "192.168.1.4:7676", "127.0.0.1:7676", "100.64.0.2:7676" ]
    end
    configured = [ { "addr" => "relay.example:7676", "label" => "community" } ]

    relays = RiceSpace::P2p::Net::Relays.discover(dht: dht, configured: configured)

    assert_equal [ "relay.example:7676", "8.8.8.8:7676" ], relays.map { |relay| relay["addr"] }
    assert_equal "community", relays.first["label"]
    assert_equal "Mainline DHT volunteer", relays.last["label"]
  end

  def test_relay_directory_keeps_configured_entries_when_dht_is_unavailable
    dht = Object.new
    dht.define_singleton_method(:find_peers) { raise RiceSpace::P2p::Error, "offline" }
    configured = [ { "addr" => "relay.example:7676", "label" => "community" } ]

    assert_equal configured, RiceSpace::P2p::Net::Relays.discover(dht: dht, configured: configured)
  end

  private

  def compact_node(id, socket)
    id + IPAddr.new("127.0.0.1").hton + [ socket.addr[1] ].pack("n")
  end

  def drain(queue)
    requests = []
    requests << queue.pop(true) until queue.empty?
    requests
  rescue ThreadError
    requests
  end

  def with_dht(values: [ "\xcb\x00\x71\x13\x1d\xf6".b ])
    socket = UDPSocket.new
    socket.bind("127.0.0.1", 0)
    node_id = "r" * 20
    requests = Queue.new
    server = Thread.new do
      sequence = nil
      loop do
        packet, peer = socket.recvfrom(4096)
        request = RiceSpace::P2p::Net::Bencode.decode(packet)
        requests << request
        args = request["a"] || {}
        response = { "id" => node_id }
        if request["q"] == "ping"
          compact = node_id + IPAddr.new("127.0.0.1").hton + [ socket.addr[1] ].pack("n")
          response["nodes"] = compact
        elsif request["q"] == "get_peers"
          response["token"] = "fresh-token"
          response["values"] = values
        elsif request["q"] == "get"
          response["token"] = "fresh-token"
          response["seq"] = sequence unless sequence.nil?
        elsif request["q"] == "put"
          sequence = args["seq"]
        end
        socket.send(RiceSpace::P2p::Net::Bencode.encode(
          { "t" => request["t"], "y" => "r", "r" => response }), 0, peer[3], peer[1])
      end
    rescue IOError, Errno::EBADF
      nil
    end
    dht = RiceSpace::P2p::Net::Dht.new
    yield dht, socket, requests
  ensure
    dht&.close
    socket&.close
    server&.kill
    server&.join
  end
end
