# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "open3"
require_relative "../lib/ricespace"

class PeerAddressTest < Minitest::Test
  def test_copyable_command_and_lan_scope
    result = RiceSpace::P2p::Address.report(public_key: "a" * 64, device_key: "b" * 64,
      host: "192.168.1.12", port: 7676, probe: ->(*) { true })
    assert_equal "192.168.1.12:7676", result["address"]
    assert_equal "same LAN; internet reachability not verified", result["scope"]
    assert_includes result["command"], "peer add #{'a' * 64} friend --at 192.168.1.12:7676"
  end

  def test_closed_listener_does_not_print_a_working_address
    error = assert_raises(RiceSpace::P2p::Error) do
      RiceSpace::P2p::Address.report(public_key: "a" * 64, device_key: "b" * 64,
        host: "192.168.1.12", port: 7676, probe: ->(*) { false })
    end
    assert_includes error.message, "peer serve"
  end

  def test_explicit_hostname_does_not_claim_internet_reachability
    result = RiceSpace::P2p::Address.report(public_key: "a" * 64, device_key: "b" * 64,
      host: "peer.example.org", port: 7676, probe: ->(*) { true })
    assert_equal "internet reachability not verified from outside this network", result["scope"]
  end

  def test_rejects_bad_ports_hosts_and_unsupported_ipv6
    [ [ "127.0.0.1", 0 ], [ "127.0.0.1", 65536 ], [ "-bad", 7676 ],
      [ "host;command", 7676 ], [ "::1", 7676 ], [ "0.0.0.0", 7676 ] ].each do |host, port|
      assert_raises(RiceSpace::P2p::Error) do
        RiceSpace::P2p::Address.report(public_key: "a" * 64, device_key: "b" * 64,
          host: host, port: port, probe: ->(*) { true })
      end
    end
  end

  def test_loopback_is_explicitly_machine_local
    result = RiceSpace::P2p::Address.report(public_key: "a" * 64, device_key: "b" * 64,
      host: "127.0.0.1", port: 7676, probe: ->(*) { true })
    assert_equal "this machine only", result["scope"]
  end

  def test_first_contact_device_pin_is_saved_and_bad_pins_are_refused
    Dir.mktmpdir do |dir|
      peers = RiceSpace::P2p::Peers.new(path: Pathname.new(dir).join("peers.json"), follows: {})
      peers.add("a" * 64, petname: "friend", addrs: [ "127.0.0.1:7676" ], device: "b" * 64)
      loaded = RiceSpace::P2p::Peers.load(dir)
      assert_equal "b" * 64, loaded.follows["a" * 64]["device"]
      assert_raises(RiceSpace::P2p::Error) do
        peers.add("c" * 64, petname: "wrong", device: "not-a-key")
      end
    end
  end

  def test_pairing_proof_cli_signs_the_exact_challenge_and_refuses_arbitrary_messages
    Dir.mktmpdir do |dir|
      identity = RiceSpace::P2p::Identity.create(dir: dir, device_name: "test",
        master_passphrase: "test-only", device_passphrase: "test-only")
      challenge = "ricespace-link-v1:https://rice.example:1:#{'b' * 64}:#{'c' * 64}"
      exe = File.expand_path("../exe/ricespace", __dir__)
      env = { "RICESPACE_CONFIG_HOME" => dir, "RICESPACE_STORE" => File.join(dir, "feeds") }
      output, _error, status = Open3.capture3(env, RbConfig.ruby, exe, "identity", "prove", challenge,
        "--json", stdin_data: "test-only\n")
      assert status.success?
      signature = JSON.parse(output).fetch("proof")
      assert RiceSpace::P2p::Keys.verify(identity.master_public, signature, challenge)
      refute RiceSpace::P2p::Keys.verify(identity.master_public, signature, "different challenge")
      _output, _error, status = Open3.capture3(env, RbConfig.ruby, exe, "identity", "prove", "arbitrary")
      refute status.success?
    end
  end

  def test_real_tls_probe_accepts_only_the_expected_device
    key = RiceSpace::P2p::Keys.generate
    server = TCPServer.new("127.0.0.1", 0)
    tls = OpenSSL::SSL::SSLServer.new(server, RiceSpace::P2p::Tls.server_context(key[:private_hex]))
    thread = Thread.new do
      2.times do
        client = tls.accept
        client.close
      end
    end
    port = server.addr[1]
    assert RiceSpace::P2p::Address.listening?("127.0.0.1", port, key[:public_hex])
    refute RiceSpace::P2p::Address.listening?("127.0.0.1", port, "0" * 64)
  ensure
    thread&.kill
    server&.close
  end
end
