# frozen_string_literal: true

require "socket"

module RiceSpace
  module P2p
    module Net
      # NAT-PMP (RFC6886, §3): ask the gateway (almost always .1) to map a
      # TCP port. The whole protocol is one 12-byte request and one 16-byte
      # reply — small enough to write in full and test against a fake.
      module Natpmp
        GATEWAY_SUFFIX = ".1"
        TIMEOUT = 3

        def self.gateway
          UDPSocket.open do |socket|
            socket.connect("192.0.2.1", 9)
            host = socket.addr[3]
            parts = host.to_s.split(".")
            return nil unless parts.size == 4

            "#{parts[0..2].join(".")}#{GATEWAY_SUFFIX}"
          end
        rescue StandardError
          nil
        end

        # Returns the mapped external port, or nil.
        def self.map(internal_port:, external_port: nil, lifetime: 3600, gateway: nil, socket: nil)
          target = gateway || self.gateway
          return nil if target.nil?

          owned = socket.nil?
          udp = socket || UDPSocket.new
          udp.connect(target, 5351) if owned
          wanted = external_port || internal_port
          # ver=0, op=2 (TCP map), reserved, internal, external, lifetime.
          request = [ 0, 2, 0, internal_port.to_i, wanted.to_i, lifetime.to_i ].pack("CCnnnN")
          udp.send(request, 0)
          ready, = IO.select([ udp ], nil, nil, TIMEOUT)
          return nil if ready.nil?

          data, = udp.recvfrom(64)
          reply = parse_reply(data.b)
          reply[:external] if reply && reply[:result] == 0
        rescue IOError, SystemCallError, SocketError
          nil
        ensure
          udp&.close if owned
        end

        def self.parse_reply(data)
          return nil if data.bytesize < 16

          ver, op, result, _epoch, external, _internal, _lifetime = data.unpack("CCnNnnN")
          return nil unless ver == 0 && (op & 0x7F) == 2

          { result: result, external: external }
        end
      end
    end
  end
end
