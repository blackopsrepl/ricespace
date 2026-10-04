# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ricespace"

# Discovery integration: publish a slot, fetch it back, verify it against
# feed history, resolve it into dial candidates. The DHT is a loopback fake
# speaking real KRPC — no live network in the suite.
class NetDiscoveryTest < Minitest::Test
  include RiceSpace::P2p::Net

  def test_publish_fetch_verify_resolve_round_trip
    master, device, feed = feed_with_device
    fake = FakeDht.new
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "127.0.0.1:18311" ], sign_with: device[:private_hex])
    packed = Endpoint.pack(record)

    assert_equal 1, fake.publish(device[:public_hex], device[:private_hex], packed)

    resolved = Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: feed.dir.parent.to_s)
    # 127.0.0.1 is lan-only and we have no LAN context: filtered.
    assert_empty resolved.select { |candidate| candidate[:via] == :dht }

    public_record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], at: Time.now.to_i + 5, sign_with: device[:private_hex])
    fake.publish(device[:public_hex], device[:private_hex], Endpoint.pack(public_record))
    resolved = Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: feed.dir.parent.to_s)

    dht_addrs = resolved.select { |candidate| candidate[:via] == :dht }
    assert_equal [ "203.0.113.7:7676" ], dht_addrs.map { |candidate| candidate[:addr] }
    assert_equal device[:public_hex], dht_addrs.first[:pin]
  end

  def test_changed_endpoint_resolves_without_manual_updates
    master, device, feed = feed_with_device
    fake = FakeDht.new
    now = Time.now.to_i
    first = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], at: now, sign_with: device[:private_hex])
    fake.publish(device[:public_hex], device[:private_hex], Endpoint.pack(first))

    moved = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "198.51.100.9:7676" ], at: now + 5, sign_with: device[:private_hex])
    fake.publish(device[:public_hex], device[:private_hex], Endpoint.pack(moved))

    resolved = Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: feed.dir.parent.to_s)
    assert_equal [ "198.51.100.9:7676" ],
      resolved.select { |candidate| candidate[:via] == :dht }.map { |candidate| candidate[:addr] }
  end

  def test_forged_revoked_and_expired_slots_never_resolve
    master, device, feed = feed_with_device
    store = feed.dir.parent.to_s
    fake = FakeDht.new

    # Forged: signed by a stranger for this node.
    stranger = RiceSpace::P2p::Keys.generate
    forged = Endpoint.build(node: master[:public_hex], device: stranger[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: stranger[:private_hex])
    fake.publish(device[:public_hex], device[:private_hex], Endpoint.pack(forged), at: 1_000)
    assert_empty dht_candidates(fake, master, store)

    # Revoked device.
    fake2 = FakeDht.new
    cutoff = feed.next_seq
    feed.append(RiceSpace::P2p::Record.build(author: master[:public_hex], signer: master[:public_hex],
      seq: feed.next_seq, prev: feed.prev_hash, kind: "device-revoke",
      body: { "device" => device[:public_hex], "cutoff_seq" => cutoff },
      sign_with: master[:private_hex]))
    revoked = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: device[:private_hex])
    fake2.publish(device[:public_hex], device[:private_hex], Endpoint.pack(revoked), at: 1_000)
    assert_empty dht_candidates(fake2, master, store)

    # Expired.
    fake3 = FakeDht.new
    stale = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], at: Time.now.to_i - 99999, sign_with: device[:private_hex])
    fake3.publish(device[:public_hex], device[:private_hex], Endpoint.pack(stale), at: 1_000)
    assert_empty dht_candidates(fake3, master, store)
  end

  def test_ticket_naming_us_emits_the_rendezvous_rung
    master, device, feed = feed_with_device
    me = RiceSpace::P2p::Keys.generate
    fake = FakeDht.new
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [], rv: [ "198.51.100.9:7676" ],
      ticket: { "relay" => "198.51.100.9:7676", "secret" => "ab12cd34ef56ab78",
        "peer" => me[:public_hex] },
      sign_with: device[:private_hex])
    fake.publish(device[:public_hex], device[:private_hex], Endpoint.pack(record))

    resolved = Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: feed.dir.parent.to_s, own_pub: me[:public_hex])
    rv = resolved.select { |candidate| candidate[:via] == :rendezvous }

    assert_equal 1, rv.size
    assert_equal "198.51.100.9:7676", rv.first[:addr]
    assert_equal "ab12cd34ef56ab78", rv.first[:ticket]["secret"]

    # A ticket for somebody else is not our rung.
    stranger = RiceSpace::P2p::Keys.generate
    resolved2 = Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: feed.dir.parent.to_s, own_pub: stranger[:public_hex])
    assert_empty resolved2.select { |candidate| candidate[:via] == :rendezvous }
  end

  def test_manual_addresses_always_win_and_survive_no_dht
    master, _device, feed = feed_with_device
    peers = peers_with(master[:public_hex], [ "192.0.2.9:7676" ])
    resolved = Discovery.resolve(peers, master[:public_hex],
      dht: nil, store_root: feed.dir.parent.to_s)

    assert_equal [ "192.0.2.9:7676" ], resolved.map { |candidate| candidate[:addr] }
    assert_equal :manual, resolved.first[:via]
  end

  private

  # A DHT with a memory store and real BEP44 signature checks on publish —
  # the fake enforces what the network enforces, nothing more.
  class FakeDht
    def initialize
      @slots = {}
    end

    def publish(device_hex, private_hex, packed, at: Time.now.to_i)
      record = RiceSpace::P2p::Net::Endpoint.unpack(packed)
      bytes = RiceSpace::P2p::Canonical.signing_bytes(author: record["node"], seq: record["at"],
        prev: record["device"], kind: "endpoint", body: record.reject { |key, _| key == "sig" })
      return 0 unless RiceSpace::P2p::Keys.verify(device_hex, record["sig"], bytes)

      key = device_hex.to_s.downcase
      return 0 if @slots[key] && @slots[key][:at] >= record["at"].to_i

      @slots[key] = { at: record["at"].to_i, v: packed }
      1
    end

    def fetch(device_hex)
      entry = @slots[device_hex.to_s.downcase]
      entry ? { seq: entry[:at], v: entry[:v] } : nil
    end
  end

  def feed_with_device
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    dir = Dir.mktmpdir
    feed = RiceSpace::P2p::Feed.new(master[:public_hex], root: dir)
    feed.append(RiceSpace::P2p::Record.build(author: master[:public_hex], signer: master[:public_hex],
      seq: 1, prev: RiceSpace::P2p::Record::GENESIS_PREV,
      kind: "device-add", body: { "device" => device[:public_hex] },
      sign_with: master[:private_hex]))
    [ master, device, feed ]
  end

  def peers_with(pub, addrs)
    RiceSpace::P2p::Peers.new(path: Pathname.new(Dir.mktmpdir).join("peers.json"),
      follows: { pub => { "petname" => "friend", "addrs" => addrs } })
  end

  def dht_candidates(fake, master, store)
    Discovery.resolve(peers_with(master[:public_hex], []), master[:public_hex],
      dht: fake, store_root: store).select { |candidate| candidate[:via] == :dht }
  end
end
