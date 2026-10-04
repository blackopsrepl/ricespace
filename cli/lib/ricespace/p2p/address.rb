# frozen_string_literal: true

require "ipaddr"
require "shellwords"
require "timeout"

module RiceSpace
  module P2p
    # A shareable endpoint, checked against the serving device's TLS key.
    # A local connection cannot prove a remote router permits inbound traffic.
    module Address
      def self.report(public_key:, device_key:, host: nil, port: 7676, probe: method(:listening?))
        host ||= local_host
        host = host.to_s
        port = Integer(port.to_s, 10)
        raise Error, "port must be between 1 and 65535" unless (1..65535).cover?(port)
        if host.include?(":")
          raise Error, "IPv6 share addresses are not supported yet; use an IPv4 address or hostname"
        end
        unless host.match?(/\A[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?\z/) && host != "0.0.0.0"
          raise Error, "use a host name or a specific IPv4 address, not a URL or wildcard"
        end
        unless probe.call(host, port, device_key)
          raise Error, "no matching peer server answers at #{host}:#{port}; start `ricespace peer serve --port #{port}` and check the address/firewall"
        end

        endpoint = "#{host}:#{port}"
        { "address" => endpoint, "scope" => scope(host), "listener" => "device key verified",
          "command" => Shellwords.join([ "ricespace", "peer", "add", public_key, "friend", "--at", endpoint,
            "--device", device_key ]) }
      rescue ArgumentError
        raise Error, "port must be an integer between 1 and 65535"
      end

      def self.local_host
        # UDP connect selects the outbound interface without sending a packet.
        UDPSocket.open do |socket|
          socket.connect("192.0.2.1", 9)
          host = socket.addr[3]
          return host unless host.start_with?("127.") || host == "0.0.0.0"
        end
        raise Error, "no routable IPv4 interface; specify --host and start peer serve"
      rescue SystemCallError, SocketError
        raise Error, "no routable IPv4 interface; specify --host and start peer serve"
      end

      def self.scope(host)
        return "this machine only" if host == "localhost"

        ip = IPAddr.new(host)
        return "this machine only" if ip.loopback?
        return "same LAN; internet reachability not verified" if ip.private? || ip.link_local?

        "internet reachability not verified from outside this network"
      rescue IPAddr::InvalidAddressError
        "internet reachability not verified from outside this network"
      end

      def self.listening?(host, port, device_key)
        tcp = ssl = nil
        Timeout.timeout(3) do
          tcp = Socket.tcp(host, port, connect_timeout: 2)
          key = Keys.generate
          ssl = OpenSSL::SSL::SSLSocket.new(tcp, Tls.client_context(key[:private_hex]))
          ssl.sync_close = true
          ssl.connect
          Tls.peer_key(ssl) == device_key
        end
      rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError, Timeout::Error, Error
        false
      ensure
        ssl&.close
        tcp&.close
      end
    end
  end
end
