# frozen_string_literal: true

require "json"
require "pathname"

module RiceSpace
  module P2p
    # Who this machine follows and where to find them. `peers.json` beside the
    # identity — manual entries (`peer add`), because v0 has no DHT and no
    # discovery beyond the LAN beacon:
    #   { "follows": { "<pubhex>": { "petname": "ron", "addrs": ["host:port"] } } }
    class Peers
      FILENAME = "peers.json"
      HINTS = "hints.json"

      def initialize(path:, follows:)
        @path = path
        @follows = follows
      end

      attr_reader :follows

      # Gossiped addresses for keys we do NOT follow: discovery, not
      # introduction. Shown by `peer list` as hints; following still takes an
      # explicit `peer add` with a human-chosen petname.
      def hints(config_dir = nil)
        file = hints_path(config_dir)
        return {} unless file.file?

        begin
          data = JSON.parse(file.read)
          data.is_a?(Hash) ? data : {}
        rescue JSON::ParserError
          {}
        end
      end

      def note_hint(pub, addrs)
        return if follow?(pub.to_s)

        file = hints_path
        known = hints
        merged = ((Array(known[pub.to_s]) + Array(addrs)).map(&:to_s).uniq)
        known[pub.to_s] = merged
        file.dirname.mkpath
        temp = Pathname.new("#{file}.new")
        temp.write(JSON.pretty_generate(known) + "\n")
        temp.chmod(0o600)
        temp.rename(file)
      end

      def hints_path(config_dir = nil)
        base = config_dir ? Pathname.new(config_dir.to_s) : @path.dirname
        base.join(HINTS)
      end

      def self.path(config_dir = Config::DIRECTORY)
        Pathname.new(config_dir.to_s).join(FILENAME)
      end

      def self.load(config_dir = Config::DIRECTORY)
        file = path(config_dir)
        follows = {}
        if file.file?
          begin
            data = JSON.parse(file.read)
            follows = data["follows"] if data.is_a?(Hash) && data["follows"].is_a?(Hash)
          rescue JSON::ParserError
            follows = {}
          end
        end
        new(path: file, follows: follows)
      end

      def follow?(public_hex)
        @follows.key?(public_hex.to_s)
      end

      def petname_for(public_hex)
        entry = @follows[public_hex.to_s]
        entry.is_a?(Hash) ? entry["petname"].to_s : ""
      end

      def addrs_for(public_hex)
        entry = @follows[public_hex.to_s]
        entry.is_a?(Hash) ? Array(entry["addrs"]).map(&:to_s) : []
      end

      def add(public_hex, petname:, addrs: [], device: nil)
        raise Error, "not an account" unless Keys.valid_public?(public_hex.to_s)
        raise Error, "not a device public key" if device && !Keys.valid_public?(device.to_s)

        name = petname.to_s.strip
        raise Error, "name the follow (a petname, for you)" if name.empty?

        entry = @follows[public_hex.to_s] || {}
        entry = entry.is_a?(Hash) ? entry : {}
        entry["petname"] = name
        entry["device"] = device if device
        entry["addrs"] = ((Array(entry["addrs"]) + Array(addrs)).map(&:to_s).uniq)
        @follows[public_hex.to_s] = entry
        save
      end

      def remove(public_hex)
        raise Error, "not followed" unless @follows.delete(public_hex.to_s)

        save
      end

      def set_addrs(public_hex, addrs)
        entry = @follows[public_hex.to_s]
        raise Error, "not followed" if entry.nil?

        entry["addrs"] = Array(addrs).map(&:to_s).uniq
        save
      end

      # Every address we know for every follow: [feed, addr, via] triples.
      # `via` is the follow whose address this is — the pin target, because
      # the serving device belongs to the node at the address, not
      # necessarily to the feed being fetched (replica path).
      def dial_list
        @follows.flat_map do |pub, entry|
          Array(entry.is_a?(Hash) ? entry["addrs"] : []).map { |addr| [ pub, addr.to_s, pub ] }
        end
      end

      private

      def save
        @path.dirname.mkpath
        temp = Pathname.new("#{@path}.new")
        temp.write(JSON.pretty_generate({ "follows" => @follows }) + "\n")
        temp.chmod(0o600)
        temp.rename(@path)
        self
      end
    end
  end
end
