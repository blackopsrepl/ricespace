# frozen_string_literal: true

require "json"
require "ipaddr"

module RiceSpace
  module P2p
    module Net
      # Well-known rendezvous relays shipped with the client: open meeting
      # points run by volunteers, not by the project owner. Same trust shape
      # as the seed keys — a first guess, replaced by DHT-learned and
      # gossiped relays, and the TLS pin still has to pass on both legs.
      # To run a public relay, add your address and get it merged: that PR
      # is the whole admission process.
      module Relays
        def self.list
          file = relays_file
          return [] unless file.file?

          data = JSON.parse(file.read)
          normalize(Array(data.is_a?(Hash) ? data["relays"] : data))
        rescue JSON::ParserError
          []
        end

        # Mainline DHT entries are untrusted addresses. Accept only globally
        # routable IPv4 volunteers; explicit configured relays may use DNS.
        def self.discover(dht:, configured: list)
          known = normalize(configured)
          discovered = dht.find_peers.filter_map do |addr|
            next unless public_ipv4?(addr)

            { "addr" => addr, "label" => "Mainline DHT volunteer" }
          end
          normalize(known + discovered).uniq { |relay| relay["addr"] }.first(16)
        rescue RiceSpace::P2p::Error
          normalize(configured)
        end

        def self.normalize(entries)
          Array(entries).filter_map do |entry|
            next unless entry.is_a?(Hash)

            addr = entry["addr"].to_s
            host, port = addr.split(":", 2)
            next if host.nil? || host.empty? || port.nil?
            next unless port.match?(/\A\d+\z/) && (1..65535).cover?(port.to_i)
            next if host.include?(":") || host.include?(" ") || host == "0.0.0.0"

            { "addr" => addr, "label" => entry["label"].to_s.strip }
          end
        end
        private_class_method :normalize

        def self.public_ipv4?(addr)
          host, port = addr.to_s.split(":", 2)
          return false unless host && port&.match?(/\A\d+\z/) && (1..65535).cover?(port.to_i)

          ip = IPAddr.new(host)
          return false unless ip.ipv4?
          return false if ip.private? || ip.loopback? || ip.link_local?

          blocked = %w[100.64.0.0/10 192.0.0.0/24 192.0.2.0/24 198.18.0.0/15
            198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4]
          blocked.none? { |range| IPAddr.new(range).include?(ip) }
        rescue IPAddr::InvalidAddressError
          false
        end
        private_class_method :public_ipv4?

        def self.relays_file
          Pathname.new(__dir__).join("relays.json")
        end
      end
    end
  end
end
