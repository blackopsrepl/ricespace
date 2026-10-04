# frozen_string_literal: true

require "net/http"
require "socket"
require "timeout"
require "uri"

module RiceSpace
  module P2p
    module Net
      # UPnP IGD port mapping: SSDP discover, fetch the device description,
      # AddPortMapping over SOAP, DeletePortMapping on exit. Every step
      # bounded; absence of an IGD is the normal case, not an error.
      module Upnp
        SSDP_ADDR = "239.255.255.250"
        SSDP_PORT = 1900
        SEARCH = "urn:schemas-upnp-org:device:InternetGatewayDevice:1"
        DISCOVER_TIMEOUT = 4
        HTTP_TIMEOUT = 5

        def self.discover
          udp = UDPSocket.new
          udp.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
          message = "M-SEARCH * HTTP/1.1\r\nHOST: #{SSDP_ADDR}:#{SSDP_PORT}\r\n" \
            "MAN: \"ns=01; ns=01\"\r\nMX: 2\r\nST: #{SEARCH}\r\n\r\n"
          udp.send(message, 0, SSDP_ADDR, SSDP_PORT)
          deadline = Time.now + DISCOVER_TIMEOUT
          locations = []
          while (left = deadline - Time.now) > 0
            ready, = IO.select([ udp ], nil, nil, left)
            break if ready.nil?

            data, = udp.recvfrom(2048)
            data.to_s.each_line do |line|
              locations << line.split(":", 2).last.strip if line =~ /\ALOCATION:/i
            end
          end
          locations.uniq
        rescue IOError, SystemCallError => error
          raise Error, "UPnP discovery failed (#{error.class})"
        ensure
          udp&.close
        end

        # Returns {location:, control_url:, service_type:} or nil. The device
        # description is a small known shape; a targeted scan avoids an XML
        # dependency for one parse (the Gemfile does not carry rexml).
        def self.describe(location)
          uri = URI(location.to_s)
          body = http_get(uri)
          body.to_s.scan(/<service>(.*?)<\/service>/m) do |inner|
            type = inner.first[/<serviceType>(.*?)<\/serviceType>/m, 1].to_s
            next unless type.include?("WANIPConnection") || type.include?("WANPPPConnection")

            control = inner.first[/<controlURL>(.*?)<\/controlURL>/m, 1].to_s
            base = "#{uri.scheme}://#{uri.host}:#{uri.port}"
            return { location: location, control_url: control.start_with?("/") ? base + control : control,
              service_type: type }
          end
          nil
        rescue StandardError
          nil
        end

        def self.map(igd, internal_port:, external_port: nil, protocol: "TCP", lease: 3600)
          external = external_port || internal_port
          envelope = <<~SOAP
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
              s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body><u:AddPortMapping xmlns:u="#{igd[:service_type]}">
                <NewRemoteHost></NewRemoteHost>
                <NewExternalPort>#{external.to_i}</NewExternalPort>
                <NewProtocol>#{protocol}</NewProtocol>
                <NewInternalPort>#{internal_port.to_i}</NewInternalPort>
                <NewInternalClient>#{internal_client}</NewInternalClient>
                <NewEnabled>1</NewEnabled>
                <NewPortMappingDescription>ricespace-p2p</NewPortMappingDescription>
                <NewLeaseDuration>#{lease.to_i}</NewLeaseDuration>
              </u:AddPortMapping></s:Body></s:Envelope>
          SOAP
          code, _body = soap(igd, "AddPortMapping", envelope)
          code == 200 ? external : nil
        rescue StandardError
          nil
        end

        def self.unmap(igd, external_port:, protocol: "TCP")
          envelope = <<~SOAP
            <?xml version="1.0"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
              s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
              <s:Body><u:DeletePortMapping xmlns:u="#{igd[:service_type]}">
                <NewRemoteHost></NewRemoteHost>
                <NewExternalPort>#{external_port.to_i}</NewExternalPort>
                <NewProtocol>#{protocol}</NewProtocol>
              </u:DeletePortMapping></s:Body></s:Envelope>
          SOAP
          code, _body = soap(igd, "DeletePortMapping", envelope)
          code == 200
        rescue StandardError
          false
        end

        def self.internal_client
          UDPSocket.open do |socket|
            socket.connect("192.0.2.1", 9)
            return socket.addr[3]
          end
        rescue StandardError
          nil
        end
        private_class_method :internal_client

        def self.http_get(uri)
          ::Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
            response = http.get(uri.request_uri)
            raise Error, "UPnP description #{response.code}" unless response.code == "200"

            response.body.to_s
          end
        end
        private_class_method :http_get

        def self.soap(igd, action, envelope)
          uri = URI(igd[:control_url].to_s)
          ::Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
            open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
            request = ::Net::HTTP::Post.new(uri.request_uri)
            request["SOAPAction"] = "\"#{igd[:service_type]}##{action}\""
            request["Content-Type"] = "text/xml; charset=utf-8"
            request.body = envelope
            response = http.request(request)
            [ response.code.to_i, response.body.to_s ]
          end
        end
        private_class_method :soap
      end
    end
  end
end
