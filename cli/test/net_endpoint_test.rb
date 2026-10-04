# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../lib/ricespace"

# Endpoint slots: build, pack, verify, and every refusal. Authorisation runs
# against real feed chains, not fixtures.
class NetEndpointTest < Minitest::Test
  include RiceSpace::P2p::Net

  def test_build_pack_verify_round_trip
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: device[:private_hex])

    packed = Endpoint.pack(record)
    assert_operator packed.bytesize, :<, 1000, "must fit a BEP44 slot"

    verified = Endpoint.verify(Endpoint.unpack(packed))
    assert_equal [ "203.0.113.7:7676" ], verified["addrs"]
  end

  def test_authorised_device_passes_against_its_feed
    master, device, feed = feed_with_device
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: device[:private_hex])

    verified = Endpoint.verify(record, chain: feed.verify)
    assert_equal device[:public_hex], verified["device"]
  end

  def test_stranger_device_is_refused
    master, _device, feed = feed_with_device
    stranger = RiceSpace::P2p::Keys.generate
    record = Endpoint.build(node: master[:public_hex], device: stranger[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: stranger[:private_hex])

    assert_raises(RiceSpace::P2p::Error) { Endpoint.verify(record, chain: feed.verify) }
  end

  def test_revoked_device_is_refused_after_cutoff
    master, device, feed = feed_with_device
    cutoff = feed.next_seq
    feed.append(RiceSpace::P2p::Record.build(author: master[:public_hex], signer: master[:public_hex],
      seq: feed.next_seq, prev: feed.prev_hash, kind: "device-revoke",
      body: { "device" => device[:public_hex], "cutoff_seq" => cutoff },
      sign_with: master_secret_for(feed, master)))
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], at: Time.now.to_i, sign_with: device[:private_hex])

    assert_raises(RiceSpace::P2p::Error) { Endpoint.verify(record, chain: feed.verify) }
  end

  def test_forged_signature_is_refused
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: device[:private_hex])
    record["addrs"] = [ "198.51.100.99:7676" ]

    assert_raises(RiceSpace::P2p::Error) { Endpoint.verify(record) }
  end

  def test_expired_and_replayed_slots_are_refused
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    old = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], at: Time.now.to_i - 99999, sign_with: device[:private_hex])

    assert_raises(RiceSpace::P2p::Error) { Endpoint.verify(old) }
  end

  def test_bad_addresses_are_refused
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    assert_raises(RiceSpace::P2p::Error) do
      Endpoint.build(node: master[:public_hex], device: device[:public_hex],
        addrs: [ "0.0.0.0:7676" ], sign_with: device[:private_hex])
    end
  end

  def test_format_2_carries_rendezvous_and_nat_labels
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    record = Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], nat: "sym",
      rv: [ "198.51.100.9:7676" ], sign_with: device[:private_hex])

    assert_equal 2, record["ep"]
    assert_equal "sym", record["nat"]
    packed = Endpoint.pack(record)
    assert_operator packed.bytesize, :<, 1000, "must still fit a BEP44 slot"
    verified = Endpoint.verify(Endpoint.unpack(packed))
    assert_equal [ "198.51.100.9:7676" ], verified["rv"]
    assert_equal "sym", verified["nat"]
  end

  def test_format_1_slots_still_verify
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    old = { "ep" => 1, "node" => master[:public_hex], "device" => device[:public_hex],
      "addrs" => [ "203.0.113.7:7676" ], "at" => Time.now.to_i,
      "exp" => Time.now.to_i + 7200, "relay" => [] }
    bytes = RiceSpace::P2p::Canonical.signing_bytes(author: old["node"], seq: old["at"],
      prev: old["device"], kind: "endpoint", body: old)
    old["sig"] = RiceSpace::P2p::Keys.sign(device[:private_hex], bytes)

    verified = Endpoint.verify(old)
    assert_equal "unknown", verified["nat"]
    assert_empty verified["rv"]
  end

  def test_bad_nat_labels_and_rv_overflow_are_refused
    master = RiceSpace::P2p::Keys.generate
    device = RiceSpace::P2p::Keys.generate
    assert_raises(RiceSpace::P2p::Error) do
      Endpoint.build(node: master[:public_hex], device: device[:public_hex],
        addrs: [ "203.0.113.7:7676" ], nat: "carrier-pigeon",
        sign_with: device[:private_hex])
    end
    assert_raises(RiceSpace::P2p::Error) do
      Endpoint.build(node: master[:public_hex], device: device[:public_hex],
        addrs: [ "203.0.113.7:7676" ],
        rv: [ "198.51.100.1:1", "198.51.100.2:1", "198.51.100.3:1" ],
        sign_with: device[:private_hex])
    end
  end

  def test_lan_only_detection
    assert Endpoint.lan_only?("192.168.1.5:7676")
    assert Endpoint.lan_only?("10.0.0.2:7676")
    refute Endpoint.lan_only?("203.0.113.7:7676")
    refute Endpoint.lan_only?("peer.example.org:7676")
  end

  private

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

  def master_secret_for(_feed, master)
    master[:private_hex]
  end
end
