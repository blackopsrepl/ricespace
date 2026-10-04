# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/ricespace"

# Candidate addresses: STUN parsing, NAT-PMP framing, NAT labels, UPnP against
# a fake IGD. Live STUN is probed separately, never asserted in the suite.
class NetNatTest < Minitest::Test
  include RiceSpace::P2p::Net

  def test_stun_parses_a_xor_mapped_address
    # A canned RFC5389 response: cookie 00112233445566778899aabb, mapped
    # 203.0.113.7:3478 (XOR'd with the magic cookie).
    cookie = [ "00112233445566778899aabb" ].pack("H*")
    ip = [ 203, 0, 113, 7 ].pack("C*").bytes.zip([ 0x21, 0x12, 0xa4, 0x42 ].cycle)
      .map { |byte, mask| byte ^ mask }.pack("C*")
    port = [ 3478 ^ 0x2112 ].pack("n")
    attr = [ 0x0020, 8 ].pack("nn") + [ 0, 1 ].pack("CC") + port + ip
    reply = [ 0x0101, attr.bytesize, 0x2112A442 ].pack("nnN") + cookie + attr

    mapped = Stun.parse_response(reply, cookie)
    assert_equal "203.0.113.7", mapped["host"]
    assert_equal 3478, mapped["port"]
  end

  def test_stun_rejects_wrong_cookie_and_short_replies
    assert_raises(RiceSpace::P2p::Error) { Stun.parse_response("short", Random.bytes(12)) }
    cookie = Random.bytes(12)
    reply = [ 0x0101, 0, 0x2112A442 ].pack("nnN") + cookie
    assert_raises(RiceSpace::P2p::Error) { Stun.parse_response(reply, Random.bytes(12)) }
  end

  def test_natpmp_parses_a_mapping_reply
    reply = [ 0, 130, 0, 0, 12_345, 7676, 3600 ].pack("CCnNnnN").b
    parsed = Natpmp.parse_reply(reply)

    assert_equal 0, parsed[:result]
    assert_equal 12_345, parsed[:external]
    assert_nil Natpmp.parse_reply("short")
  end

  def test_natpmp_maps_against_a_fake_gateway
    server = UDPSocket.new
    server.bind("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      data, from = server.recvfrom(64)
      ver, op = data.unpack("CC")
      # ver=0, op=130 (TCP response), result=0, epoch, external, internal, lifetime.
      server.send([ 0, 128 + op, 0, 0, 9999, 7676, 3600 ].pack("CCnNnnN"), 0, from[3], from[1])
      assert_equal 0, ver
    end
    sock = UDPSocket.new
    sock.connect("127.0.0.1", port)
    mapped = Natpmp.map(internal_port: 7676, gateway: "127.0.0.1", socket: sock)
    thread.join(3)

    assert_equal 9999, mapped
  ensure
    server&.close
  end

  def test_nat_labels_stable_vs_symmetric_mappings
    stable = Nat.characterise(port: 7676, upnp: silent_upnp, natpmp: silent_natpmp,
      stun: fake_stun({ "host" => "203.0.113.7", "port" => 40001 },
        { "host" => "203.0.113.7", "port" => 40001 }))
    assert_equal "endpoint-independent-mapping", stable.label

    symmetric = Nat.characterise(port: 7676, upnp: silent_upnp, natpmp: silent_natpmp,
      stun: fake_stun({ "host" => "203.0.113.7", "port" => 40001 },
        { "host" => "203.0.113.7", "port" => 40002 }))
    assert_equal "symmetric-nat", symmetric.label

    silent = Nat.characterise(port: 7676, upnp: silent_upnp, natpmp: silent_natpmp, stun: silent_stun)
    assert_equal "unknown", silent.label
  end

  def test_upnp_maps_against_a_fake_igd
    igd = fake_igd
    external = Upnp.map(igd, internal_port: 7676)

    assert_equal 7676, external
    assert Upnp.unmap(igd, external_port: 7676)
  end

  def test_upnp_describe_finds_the_wan_service
    desc = <<~XML
      <?xml version="1.0"?>
      <root><device><serviceList>
        <service><serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
        <controlURL>/ctl/common</controlURL></service>
        <service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType>
        <controlURL>/ctl/ip</controlURL></service>
      </serviceList></device></root>
    XML
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      client = server.accept
      while (line = client.gets)
        break if line == "\r\n"
      end
      client.write("HTTP/1.1 200 OK\r\nContent-Length: #{desc.bytesize}\r\nConnection: close\r\n\r\n#{desc}")
      client.close
    end
    igd = Upnp.describe("http://127.0.0.1:#{port}/desc.xml")
    thread.join(3)

    assert_equal "urn:schemas-upnp-org:service:WANIPConnection:1", igd[:service_type]
    assert_equal "http://127.0.0.1:#{port}/ctl/ip", igd[:control_url]
  ensure
    server&.close
  end

  private

  def fake_stun(first, second)
    calls = 0
    stub = Object.new
    stub.define_singleton_method(:observe) do |*|
      calls += 1
      raise RiceSpace::P2p::Error, "silent" if first.nil?

      calls == 1 ? first : second
    end
    stub
  end

  def silent_stun
    stub = Object.new
    stub.define_singleton_method(:observe) { |*| raise RiceSpace::P2p::Error, "silent" }
    stub
  end

  def silent_upnp
    stub = Object.new
    stub.define_singleton_method(:discover) { [] }
    stub
  end

  def silent_natpmp
    stub = Object.new
    stub.define_singleton_method(:map) { |*| nil }
    stub
  end

  def fake_igd
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      2.times do
        client = server.accept
        length = 0
        while (line = client.gets)
          match = line.match(/Content-Length: (\d+)/i)
          length = match[1].to_i if match
          break if line == "\r\n"
        end
        client.read(length) if length.positive?
        body = "<ok/>"
        client.write("HTTP/1.1 200 OK\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        client.close
      end
    end
    @igd_threads ||= []
    @igd_threads << [ server, thread ]
    { location: "http://127.0.0.1:#{port}/desc.xml",
      control_url: "http://127.0.0.1:#{port}/ctl",
      service_type: "urn:schemas-upnp-org:service:WANIPConnection:1" }
  end
end
