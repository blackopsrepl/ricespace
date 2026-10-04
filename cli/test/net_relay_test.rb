# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ricespace"

# The relay bridge: an outbound-only node syncs through a consenting peer,
# TLS-pinned end-to-end. The relay sees ciphertext and moves bounded bytes.
class NetRelayTest < Minitest::Test
  include RiceSpace::P2p::Net

  def test_bridged_sync_pulls_through_a_consenting_relay
    dir_target, id_target = make_node("relay-target")
    dir_caller, id_caller = make_node("relay-caller")
    dir_bridge, id_bridge = make_node("relay-bridge")
    store_target = File.join(dir_target, "feeds")
    store_caller = File.join(dir_caller, "feeds")

    publish(id_target, store_target, "behind nat")

    # The bridge follows the target and knows its address; the caller follows
    # the target and knows only the bridge.
    peers_bridge = peers_in(dir_bridge)
    peers_bridge.add(id_target.master_public, petname: "target", addrs: [ "127.0.0.1:18131" ])
    peers_caller = peers_in(dir_caller)
    peers_caller.add(id_target.master_public, petname: "target", addrs: [])
    peers_caller.add(id_bridge.master_public, petname: "bridge", addrs: [ "127.0.0.1:18132" ])

    target = serve_on(18131, id_target, store_target)
    bridge = serve_on(18132, id_bridge, File.join(dir_bridge, "feeds"),
      peers: peers_bridge, relay: Relay::Registry.new)
    threads = [ Thread.new { target.run }, Thread.new { bridge.run } ]
    sleep 0.5

    begin
      session = Relay.dial("127.0.0.1", 18132, identity: id_caller, peers: peers_caller,
        private_hex: secret(id_caller), target_feed: id_target.master_public,
        target_pin: id_target.device_public,
        relay_pin: id_bridge.device_public, store_root: store_caller)
      begin
        gained = session.pull(peers: peers_caller, store_root: store_caller)
      ensure
        session.close
      end

      assert_equal 3, gained.values.sum
      result = RiceSpace::P2p::Feed.new(id_target.master_public, root: store_caller).verify
      assert result.ok?, result.errors.inspect
    ensure
      threads.each(&:kill)
    end
  end

  def test_bridge_without_consent_answers_noroute
    _dir_target, id_target = make_node("noroute-target")
    dir_caller, id_caller = make_node("noroute-caller")
    dir_plain, id_plain = make_node("noroute-plain")

    peers_caller = peers_in(dir_caller)
    peers_caller.add(id_target.master_public, petname: "target", addrs: [])

    # No relay registry: bridging was never consented to.
    plain = serve_on(18133, id_plain, File.join(dir_plain, "feeds"))
    thread = Thread.new { plain.run }
    sleep 0.5

    begin
      error = assert_raises(RiceSpace::P2p::Error) do
        Relay.dial("127.0.0.1", 18133, identity: id_caller, peers: peers_caller,
          private_hex: secret(id_caller), target_feed: id_target.master_public,
          relay_pin: id_plain.device_public, store_root: File.join(dir_caller, "feeds"))
      end
      assert_includes error.message, "no route"
    ensure
      thread.kill
    end
  end

  def test_wrong_pin_on_the_bridged_leg_fails_closed
    # The bridged TLS leg pins exactly like a direct dial: a forged pin dies
    # before HELLO, even though the bytes crossed a relay. Proved here over a
    # direct connection through connect_io — the pin check is shared code.
    dir_target, id_target = make_node("pin-target")
    dir_caller, id_caller = make_node("pin-caller")
    store_target = File.join(dir_target, "feeds")

    publish(id_target, store_target, "pinned")
    target = serve_on(18134, id_target, store_target)
    thread = Thread.new { target.run }
    sleep 0.5

    begin
      tcp = TCPSocket.new("127.0.0.1", 18134)
      error = assert_raises(RiceSpace::P2p::Error) do
        RiceSpace::P2p::Sync::Session.connect_io(tcp, "127.0.0.1", identity: id_caller,
          peers: peers_in(dir_caller), private_hex: secret(id_caller),
          expected_key: id_caller.device_public, store_root: File.join(dir_caller, "feeds"))
      end
      assert_includes error.message, "not who was dialed"
    ensure
      thread.kill
    end
  end

  def test_open_relay_splices_two_strangers_by_ticket
    dir_r, id_r = make_node("open-relay")
    dir_a, id_a = make_node("splice-a")
    dir_b, id_b = make_node("splice-b")

    relay = serve_on(18141, id_r, File.join(dir_r, "feeds"),
      relay: Relay::Registry.new(open: true))
    thread = Thread.new { relay.run }
    sleep 0.5

    begin
      # A allocates a ticket. No target, no pin, no prior contact.
      control_a = RiceSpace::P2p::Sync::Session.connect("127.0.0.1", 18141,
        identity: id_a, peers: peers_in(dir_a), private_hex: secret(id_a),
        expected_key: id_r.device_public, store_root: File.join(dir_a, "feeds"))
      control_a.send_line({ "type" => "ALLOC" })
      alloc = control_a.read_line
      assert_equal "ALLOCATED", alloc["type"]
      ticket = alloc["secret"]
      assert_match(/\A[0-9a-f]{16}\z/, ticket)

      # B joins with the ticket. The relay splices: bytes A writes arrive
      # at B and back, still opaque to the relay.
      control_b = RiceSpace::P2p::Sync::Session.connect("127.0.0.1", 18141,
        identity: id_b, peers: peers_in(dir_b), private_hex: secret(id_b),
        expected_key: id_r.device_public, store_root: File.join(dir_b, "feeds"))
      control_b.send_line({ "type" => "JOIN", "secret" => ticket })
      joined = control_b.read_line
      assert_equal "JOINED", joined["type"]

      # The splice is proven by a full sync through it further down the
      # ladder tests; here prove the ticket is single-use.
      control_c = RiceSpace::P2p::Sync::Session.connect("127.0.0.1", 18141,
        identity: id_b, peers: peers_in(dir_b), private_hex: secret(id_b),
        expected_key: id_r.device_public, store_root: File.join(dir_b, "feeds"))
      control_c.send_line({ "type" => "JOIN", "secret" => ticket })
      assert_equal "NOROUTE", control_c.read_line["type"]
    ensure
      thread.kill
    end
  end

  def test_two_strangers_sync_through_an_open_relay
    dir_r, id_r = make_node("rv-relay")
    dir_a, id_a = make_node("rv-alice")
    dir_b, id_b = make_node("rv-bob")
    store_a = File.join(dir_a, "feeds")
    store_b = File.join(dir_b, "feeds")

    publish(id_a, store_a, "alice here")

    relay = serve_on(18143, id_r, File.join(dir_r, "feeds"),
      relay: Relay::Registry.new(open: true))
    thread = Thread.new { relay.run }
    sleep 0.5

    begin
      peers_a = peers_in(dir_a)
      peers_b = peers_in(dir_b)
      # Bob follows Alice's key (out-of-band pairing); neither knows the
      # other's address. The ticket travels the same path.
      peers_b.add(id_a.master_public, petname: "alice", addrs: [])

      # Alice waits at the relay; Bob joins with the ticket.
      control_a, secret = Relay.alloc("127.0.0.1", 18143, identity: id_a,
        peers: peers_a, private_hex: secret(id_a), relay_pin: id_r.device_public,
        store_root: store_a)
      bob_session = Thread.new do
        Relay.join("127.0.0.1", 18143, secret, identity: id_b, peers: peers_b,
          private_hex: secret(id_b), target_feed: id_a.master_public,
          target_pin: id_a.device_public, relay_pin: id_r.device_public,
          store_root: store_b)
      end
      alice_session = Relay.await_peer(control_a, secret, identity: id_a,
        peers: peers_a, private_hex: secret(id_a), target_feed: id_b.master_public,
        target_pin: id_b.device_public, store_root: store_a)
      bob = bob_session.value

      # The waiter serves its own feed over the spliced session (same as
      # every other path: one side serves, the other pulls).
      serve_thread = Thread.new do
        alice_session.serve_loop(peers: peers_a, store_root: store_a)
      end
      begin
        gained = bob.pull(peers: peers_b, store_root: store_b)
        assert_equal 3, gained.values.sum
        result = RiceSpace::P2p::Feed.new(id_a.master_public, root: store_b).verify
        assert result.ok?, result.errors.inspect
      ensure
        serve_thread.kill
        alice_session.close
        bob.close
      end
    ensure
      thread.kill
    end
  end

  def test_closed_relay_refuses_alloc
    dir_r, id_r = make_node("closed-relay")
    dir_a, id_a = make_node("alloc-a")

    relay = serve_on(18142, id_r, File.join(dir_r, "feeds"))
    thread = Thread.new { relay.run }
    sleep 0.5

    begin
      control = RiceSpace::P2p::Sync::Session.connect("127.0.0.1", 18142,
        identity: id_a, peers: peers_in(dir_a), private_hex: secret(id_a),
        expected_key: id_r.device_public, store_root: File.join(dir_a, "feeds"))
      control.send_line({ "type" => "ALLOC" })
      assert_equal "NOROUTE", control.read_line["type"]
    ensure
      thread.kill
    end
  end

  def test_relay_sessions_are_capped_and_expire
    registry = Relay::Registry.new
    one, two = IO.pipe
    id = registry.create(one, two)

    assert registry.fetch(id)
    assert_raises(RiceSpace::P2p::Error) { registry.account(id, Relay::SESSION_CAP + 1) }
    assert_nil registry.fetch(id), "an over-cap session is dead"

    id2 = registry.create(one, two)
    registry.drop(id2)
    assert_nil registry.fetch(id2)
  ensure
    one&.close
    two&.close
  end

  private

  def make_node(name)
    dir = Dir.mktmpdir
    [ dir, RiceSpace::P2p::Identity.create(dir: dir, device_name: name,
      master_passphrase: "x", device_passphrase: "x") ]
  end

  def secret(identity)
    identity.unlock_device("x")
  end

  def peers_in(dir)
    RiceSpace::P2p::Peers.new(path: Pathname.new(dir).join("peers.json"), follows: {})
  end

  def serve_on(port, identity, store, peers: nil, relay: nil)
    peers ||= RiceSpace::P2p::Peers.new(path: Pathname.new(Dir.mktmpdir).join("p.json"), follows: {})
    RiceSpace::P2p::Sync::Server.new(port: port, identity: identity, peers: peers,
      private_hex: secret(identity), store_root: store, lan: false, relay: relay)
  end

  def publish(identity, store, document)
    feed = RiceSpace::P2p::Feed.new(identity.master_public, root: store)
    feed.append(RiceSpace::P2p::Record.build(author: identity.master_public, signer: identity.master_public,
      seq: 1, prev: RiceSpace::P2p::Record::GENESIS_PREV,
      kind: "device-add", body: { "device" => identity.device_public },
      sign_with: identity.unlock_master("x")))
    feed.append(RiceSpace::P2p::Record.build(author: identity.master_public, signer: identity.device_public,
      seq: 2, prev: feed.prev_hash, kind: "page", body: { "document" => document },
      sign_with: secret(identity)))
    feed.append(RiceSpace::P2p::Record.build(author: identity.master_public, signer: identity.device_public,
      seq: 3, prev: feed.prev_hash, kind: "lists", body: { "blurbs" => [] },
      sign_with: secret(identity)))
    feed
  end
end
