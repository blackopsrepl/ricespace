# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "tmpdir"
require "timeout"
require_relative "../lib/ricespace"

class NetRendezvousTest < Minitest::Test
  def test_ordinary_peer_service_allocates_and_serves_a_follow_over_a_volunteer
    alice_dir, alice = make_identity("alice")
    bob_dir, bob = make_identity("bob")
    relay_dir, relay_identity = make_identity("relay")
    alice_store = File.join(alice_dir, "feeds")
    bob_store = File.join(bob_dir, "feeds")
    relay_store = File.join(relay_dir, "feeds")
    publish_feed(alice, alice_store, "Alice")
    publish_feed(bob, bob_store, "Bob")
    alice_peers = empty_peers(alice_dir)
    bob_peers = peers_for(bob_dir, alice)

    relay_port = free_port
    relay_server = RiceSpace::P2p::Sync::Server.new(port: relay_port,
      identity: relay_identity, peers: empty_peers(relay_dir),
      private_hex: relay_identity.unlock_device("x"), store_root: relay_store,
      lan: false, relay: RiceSpace::P2p::Net::Relay::Registry.new(open: true))
    relay_thread = Thread.new { relay_server.run }
    relay_thread.report_on_exception = false
    wait_for_port(relay_port)

    tickets = Queue.new
    agent = RiceSpace::P2p::Net::RendezvousAgent.new(identity: alice, peers: alice_peers,
      private_hex: alice.unlock_device("x"), store_root: alice_store,
      relay_source: -> { [ "127.0.0.1:#{relay_port}" ] },
      peers_loader: -> { RiceSpace::P2p::Peers.load(alice_dir) },
      ticket_publisher: ->(peer, ticket) { tickets << [ peer, ticket ]; true },
      retry_interval: 0.05, follow_poll_interval: 0.05)
    alice_port = free_port
    alice_server = RiceSpace::P2p::Sync::Server.new(port: alice_port, identity: alice,
      peers: alice_peers, private_hex: alice.unlock_device("x"), store_root: alice_store,
      lan: false, auto_rendezvous: true, rendezvous_agent: agent)
    alice_thread = Thread.new { alice_server.run }
    alice_thread.report_on_exception = false
    wait_for_port(alice_port)
    alice_peers.add(bob.master_public, petname: "bob", device: bob.device_public)

    peer, ticket = Timeout.timeout(8) { tickets.pop }
    assert_equal bob.master_public, peer
    assert_equal bob.master_public, ticket["peer"]
    assert_operator ticket["expires"], :>, Time.now.to_i

    session = RiceSpace::P2p::Net::Relay.join("127.0.0.1", relay_port, ticket["secret"],
      identity: bob, peers: bob_peers, private_hex: bob.unlock_device("x"),
      target_feed: alice.master_public, target_pin: alice.device_public,
      relay_pin: :none, store_root: bob_store)
    gained = session.pull(peers: bob_peers, store_root: bob_store)

    assert_equal 2, gained[alice.master_public]
    assert_equal 2, RiceSpace::P2p::Feed.new(alice.master_public, root: bob_store).head["seq"]
  ensure
    session&.close
    alice_thread&.kill
    alice_thread&.join
    agent&.stop
    relay_thread&.kill
    relay_thread&.join
  end

  def test_ticket_publisher_keeps_base_slot_and_writes_pair_scoped_slot
    dir, identity = make_identity("publisher")
    root = File.join(dir, "feeds")
    publish_feed(identity, root, "publisher")
    target = RiceSpace::P2p::Keys.generate[:public_hex]
    dht = MemoryDht.new
    agent = RiceSpace::P2p::Net::RendezvousAgent.new(identity: identity,
      peers: empty_peers(dir), private_hex: identity.unlock_device("x"),
      store_root: root, relay_source: -> { [] }, dht_factory: -> { dht })
    ticket = { "relay" => "203.0.113.19:7676", "secret" => "1234567890abcdef",
      "peer" => target, "expires" => Time.now.to_i + 60 }

    assert agent.send(:publish_ticket, target, ticket)
    base = RiceSpace::P2p::Net::Endpoint.verify(
      RiceSpace::P2p::Net::Endpoint.unpack(dht.fetch(identity.device_public)[:v]),
      chain: RiceSpace::P2p::Feed.new(identity.master_public, root: root).verify)
    pair = dht.fetch(identity.device_public,
      salt: RiceSpace::P2p::Net::Dht.rendezvous_salt(target))
    rendezvous = RiceSpace::P2p::Net::Endpoint.verify(
      RiceSpace::P2p::Net::Endpoint.unpack(pair[:v]),
      chain: RiceSpace::P2p::Feed.new(identity.master_public, root: root).verify)

    assert_equal identity.master_public, base["node"]
    assert_equal ticket, rendezvous["ticket"]
  end

  def test_sync_server_owns_auto_rendezvous_and_open_relay_lifecycle
    dir, identity = make_identity("server")
    events = Queue.new
    agent = lifecycle(events, :agent)
    announcer = lifecycle(events, :announcer)
    server = RiceSpace::P2p::Sync::Server.new(port: free_port, identity: identity,
      peers: empty_peers(dir), private_hex: identity.unlock_device("x"),
      store_root: File.join(dir, "feeds"), lan: false,
      relay: RiceSpace::P2p::Net::Relay::Registry.new(open: true),
      auto_rendezvous: true, rendezvous_agent: agent, relay_announcer: announcer)
    thread = Thread.new { server.run }
    thread.report_on_exception = false
    wait_for_port(server.instance_variable_get(:@port))
    thread.kill
    thread.join

    assert_equal [ :agent_start, :announcer_start, :agent_stop, :announcer_stop ],
      4.times.map { Timeout.timeout(2) { events.pop } }
  end

  def test_stop_closes_a_ticket_connection_allocated_during_shutdown
    dir, identity = make_identity("shutdown")
    target_dir, target = make_identity("follower")
    allocated = Queue.new
    release = Queue.new
    published = Queue.new
    closed = Queue.new
    control = Object.new
    control.define_singleton_method(:close) { closed << true }
    agent = RiceSpace::P2p::Net::RendezvousAgent.new(identity: identity,
      peers: peers_for(dir, target), private_hex: identity.unlock_device("x"),
      relay_source: -> { [] }, ticket_publisher: ->(*args) { published << args; false })
    agent.define_singleton_method(:allocate_ticket) do
      allocated << true
      release.pop
      [ control, "1234567890abcdef", "relay.example:7676" ]
    end
    agent.start
    Timeout.timeout(2) { allocated.pop }

    agent.stop
    release << true

    assert Timeout.timeout(2) { closed.pop }
    assert_raises(ThreadError) { published.pop(true) }
  ensure
    agent&.stop
    FileUtils.remove_entry(dir) if dir && File.directory?(dir)
    FileUtils.remove_entry(target_dir) if target_dir && File.directory?(target_dir)
  end

  def test_open_relay_announcer_repeats_until_stopped
    announcements = Queue.new
    dht = Object.new
    dht.define_singleton_method(:bootstrap) { 1 }
    dht.define_singleton_method(:announce_peer) { |port:| announcements << port; 1 }
    dht.define_singleton_method(:close) { nil }
    announcer = RiceSpace::P2p::Net::RelayAnnouncer.new(port: 7676,
      dht_factory: -> { dht }, interval: 0.05).start

    assert_equal 7676, Timeout.timeout(2) { announcements.pop }
    assert_equal 7676, Timeout.timeout(2) { announcements.pop }
  ensure
    announcer&.stop
  end

  private

  class MemoryDht
    def initialize
      @slots = {}
    end

    def bootstrap
      1
    end

    def fetch(device, salt: RiceSpace::P2p::Net::Dht::SALT)
      @slots[[ device, salt ]]
    end

    def publish(device, private_hex, value, salt: RiceSpace::P2p::Net::Dht::SALT)
      record = RiceSpace::P2p::Net::Endpoint.unpack(value)
      bytes = RiceSpace::P2p::Canonical.signing_bytes(author: record["node"],
        seq: record["at"], prev: record["device"], kind: "endpoint",
        body: record.reject { |key, _| key == "sig" })
      return 0 unless RiceSpace::P2p::Keys.verify(device, record["sig"], bytes)

      seq = (@slots[[ device, salt ]]&.fetch(:seq, 0) || 0) + 1
      @slots[[ device, salt ]] = { seq: seq, v: value }
      1
    end

    def close
      nil
    end
  end

  def lifecycle(events, name)
    Object.new.tap do |object|
      object.define_singleton_method(:start) { events << :"#{name}_start"; self }
      object.define_singleton_method(:stop) { events << :"#{name}_stop"; self }
    end
  end

  def make_identity(name)
    dir = Dir.mktmpdir
    [ dir, RiceSpace::P2p::Identity.create(dir: dir, device_name: name,
      master_passphrase: "x", device_passphrase: "x") ]
  end

  def publish_feed(identity, root, title)
    feed = RiceSpace::P2p::Feed.new(identity.master_public, root: root)
    feed.append(RiceSpace::P2p::Record.build(author: identity.master_public,
      signer: identity.master_public, seq: 1, prev: RiceSpace::P2p::Record::GENESIS_PREV,
      kind: "device-add", body: { "device" => identity.device_public },
      sign_with: identity.unlock_master("x")))
    feed.append(RiceSpace::P2p::Record.build(author: identity.master_public,
      signer: identity.device_public, seq: 2, prev: feed.prev_hash, kind: "page",
      body: { "document" => "<h1>#{title}</h1>" }, sign_with: identity.unlock_device("x")))
  end

  def peers_for(dir, target)
    RiceSpace::P2p::Peers.new(path: Pathname.new(dir).join("peers.json"), follows: {
      target.master_public => { "petname" => target.device_name, "device" => target.device_public, "addrs" => [] }
    })
  end

  def empty_peers(dir)
    RiceSpace::P2p::Peers.new(path: Pathname.new(dir).join("peers.json"), follows: {})
  end

  def free_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server&.close
  end

  def wait_for_port(port)
    Timeout.timeout(3) do
      loop do
        begin
          socket = TCPSocket.new("127.0.0.1", port)
          socket.close
          break
        rescue SystemCallError
          sleep 0.01
        end
      end
    end
  end
end
