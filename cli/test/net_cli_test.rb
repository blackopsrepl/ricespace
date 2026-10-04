# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "open3"
require_relative "../lib/ricespace"

# The CLI surface: net up/down, peer status, and the ladder flags.
class NetCliTest < Minitest::Test
  def test_help_lists_net_and_status
    out, _err, status = run_cli("help")

    assert status.success?
    assert_includes out, "net up"
    assert_includes out, "peer status"
    assert_includes out, "--relay"
  end

  def test_peer_status_shows_never_synced_follow
    with_identity do |dir|
      friend = RiceSpace::P2p::Keys.generate
      peers = RiceSpace::P2p::Peers.load(dir)
      peers.add(friend[:public_hex], petname: "ron", addrs: [ "192.0.2.9:7676" ])

      out, _err, status = run_cli("peer", "status", env: { "RICESPACE_CONFIG_HOME" => dir })
      assert status.success?
      assert_includes out, "RON"
      assert_includes out, "never synced"
    end
  end

  def test_peer_status_privacy_explains_exposure
    with_identity do |dir|
      out, _err, status = run_cli("peer", "status", "--privacy", env: { "RICESPACE_CONFIG_HOME" => dir })
      assert status.success?
      assert_includes out, "feed contents"
      assert_includes out, "follow lists"
    end
  end

  def test_net_down_is_honest_about_expiry
    with_identity do |dir|
      out, _err, status = run_cli("net", "down", env: { "RICESPACE_CONFIG_HOME" => dir })
      assert status.success?
      assert_includes out, "2 h"
    end
  end

  def test_peer_serve_offers_relay_flag_in_help
    # Serve blocks, so prove the flag parses by its refusal shape instead:
    # --relay with no identity must fail on identity, not on the flag.
    out, err, status = run_cli("peer", "serve", "--relay",
      env: { "RICESPACE_CONFIG_HOME" => Dir.mktmpdir })

    refute status.success?
    assert_includes out + err, "identity"
  end

  def test_net_wait_needs_a_follow_and_a_relay
    with_identity do |dir|
      out, err, status = run_cli("net", "wait", env: { "RICESPACE_CONFIG_HOME" => dir })
      refute status.success?
      assert_includes out + err, "who is coming"

      friend = RiceSpace::P2p::Keys.generate[:public_hex]
      peers = RiceSpace::P2p::Peers.load(dir)
      peers.add(friend, petname: "ron", addrs: [])
      out, err, status = run_cli("net", "wait", friend, env: { "RICESPACE_CONFIG_HOME" => dir })
      refute status.success?
      assert_includes out + err, "no rendezvous relay"
    end
  end

  def test_net_wait_lists_in_help
    out, _err, status = run_cli("help")

    assert status.success?
    assert_includes out, "net wait"
    assert_includes out, "--relay-open"
  end

  def test_shipped_relay_list_loads_and_rejects_garbage
    relays = RiceSpace::P2p::Net::Relays.list

    assert relays.is_a?(Array)
    assert relays.all? { |entry| entry["addr"].match?(/\A[^:]+:\d+\z/) }
  end

  def test_endpoint_fields_survive_a_peers_round_trip
    Dir.mktmpdir do |dir|
      peers = RiceSpace::P2p::Peers.new(path: Pathname.new(dir).join("peers.json"), follows: {})
      key = RiceSpace::P2p::Keys.generate[:public_hex]
      peers.add(key, petname: "ron", addrs: [ "192.0.2.9:7676" ])
      peers.note_endpoint(key, addrs: [ "203.0.113.7:7676" ], relay: [ "198.51.100.9:7676" ],
        at: 1_700_000_000, exp: 1_700_007_200)

      loaded = RiceSpace::P2p::Peers.load(dir)
      assert_equal [ "198.51.100.9:7676" ], loaded.relays_for(key)
      assert_includes loaded.addrs_for(key), "203.0.113.7:7676"
      assert_includes loaded.addrs_for(key), "192.0.2.9:7676"
    end
  end

  private

  def with_identity
    Dir.mktmpdir do |dir|
      RiceSpace::P2p::Identity.create(dir: dir, device_name: "test",
        master_passphrase: "x", device_passphrase: "x")
      yield dir
    end
  end

  def run_cli(*args, env: {})
    exe = File.expand_path("../exe/ricespace", __dir__)
    base = { "RICESPACE_CONFIG_HOME" => Dir.mktmpdir,
      "RICESPACE_STORE" => File.join(Dir.mktmpdir, "feeds") }.merge(env)
    Open3.capture3(base, RbConfig.ruby, exe, *args, stdin_data: "")
  end
end
