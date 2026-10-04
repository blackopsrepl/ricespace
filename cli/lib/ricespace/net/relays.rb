# frozen_string_literal: true

require "json"

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
          Array(data.is_a?(Hash) ? data["relays"] : data).filter_map do |entry|
            next unless entry.is_a?(Hash)

            addr = entry["addr"].to_s
            host, port = addr.split(":", 2)
            next if host.nil? || host.empty? || port.nil?
            next unless port.match?(/\A\d+\z/) && (1..65535).cover?(port.to_i)
            next if host.include?(":") || host.include?(" ") || host == "0.0.0.0"

            { "addr" => addr, "label" => entry["label"].to_s.strip }
          end
        rescue JSON::ParserError
          []
        end

        def self.relays_file
          Pathname.new(__dir__).join("relays.json")
        end
      end
    end
  end
end
