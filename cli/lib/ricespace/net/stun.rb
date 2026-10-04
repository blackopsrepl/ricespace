# frozen_string_literal: true

require "socket"
require "timeout"

module RiceSpace
  module P2p
    module Net
      # STUN binding client (RFC5389, §6): one 20-byte request, parse the
      # XOR-MAPPED-ADDRESS. Answers "what does the internet see for this
      # socket" — observation, never proof of inbound reachability.
      module Stun
        MAGIC = 0x2112A442
        BINDING_REQUEST = 0x0001
        BINDING_RESPONSE = 0x0101
        TIMEOUT = 4

        SERVERS = [
          [ "stun.l.google.com", 19302 ],
          [ "stun1.l.google.com", 19302 ]
        ].freeze

        def self.observe(server: nil, port: nil, socket: nil)
          host, port = server ? [ server, port || 19302 ] : SERVERS.first
          owned = socket.nil?
          udp = socket || UDPSocket.new
          cookie = Random.bytes(12).b
          header = [ BINDING_REQUEST, 0, MAGIC ].pack("nnN") + cookie
          udp.connect(host.to_s, port.to_i) if owned
          udp.send(header, 0)
          ready, = IO.select([ udp ], nil, nil, TIMEOUT)
          raise Error, "STUN to #{host}:#{port} timed out" if ready.nil?

          data, = udp.recvfrom(512)
          parse_response(data.b, cookie)
        rescue IOError, SystemCallError, SocketError => error
          raise Error, "STUN to #{host}:#{port} failed (#{error.class})"
        ensure
          udp&.close if owned
        end

        def self.parse_response(data, cookie)
          raise Error, "STUN reply too short" if data.bytesize < 20

          type, length, magic, echo = data.unpack("nnNa12")
          raise Error, "not a STUN binding response" unless type == BINDING_RESPONSE
          raise Error, "STUN cookie mismatch" unless magic == MAGIC && echo == cookie

          cursor = 20
          stop = 20 + length
          while cursor + 4 <= stop && cursor + 4 <= data.bytesize
            attr, size, = data.byteslice(cursor, 4).unpack("nn")
            value = data.byteslice(cursor + 4, size).to_s.b
            if attr == 0x0020 && value.bytesize >= 8 # XOR-MAPPED-ADDRESS
              family = value.getbyte(1)
              port = value.byteslice(2, 2).unpack1("n") ^ (MAGIC >> 16)
              if family == 0x01
                ip = value.byteslice(4, 4).bytes.zip([ MAGIC ].pack("N").bytes)
                  .map { |byte, mask| byte ^ mask }.join(".")
                return { "host" => ip, "port" => port }
              end
            end
            cursor += 4 + ((size + 3) / 4) * 4
          end
          raise Error, "no mapped address in STUN reply"
        end
      end
    end
  end
end
