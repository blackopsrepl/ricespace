# frozen_string_literal: true

require "json"

module RiceSpace
  module P2p
    # Well-known peers shipped with the client: the trust anchor for *who*,
    # not *where*. Keys never change; addresses do, so treat them as a first
    # guess — gossip and the LAN beacon correct them, and the TLS pin still
    # has to pass. To run a public peer, add your key and a stable address
    # here and get it merged: that PR is the whole admission process.
    module Seeds
      def self.list
        file = seeds_file
        return [] unless file.file?

        data = JSON.parse(file.read)
        Array(data.is_a?(Hash) ? data["seeds"] : data).filter_map do |entry|
          next unless entry.is_a?(Hash) && Keys.valid_public?(entry["key"].to_s)

          { "key" => entry["key"].to_s.downcase,
            "petname" => entry["petname"].to_s.strip,
            "addrs" => Array(entry["addrs"]).map(&:to_s).uniq }
        end
      rescue JSON::ParserError
        []
      end

      def self.seeds_file
        here = Pathname.new(__dir__)
        here.join("seeds.json")
      end
    end
  end
end
