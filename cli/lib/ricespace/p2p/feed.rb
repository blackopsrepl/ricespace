# frozen_string_literal: true

require "json"
require "pathname"
require "fileutils"

module RiceSpace
  module P2p
    # One feed on this machine: the signed records, in order, one file each.
    #
    # This is the whole database of the P2P design. No tables, no migrations —
    # a directory of JSON. `verify_chain` from Record is the only reader that
    # matters: if the chain does not verify, the feed is not trusted, however it
    # got here (sync, USB stick, hand-edited).
    class Feed
      # The machine's replica of every feed it holds: its own and every follow's.
      # Overridable with RICESPACE_STORE for tests.
      def self.root(_config_dir = nil)
        base = ENV["RICESPACE_STORE"]
        return Pathname.new(base) unless base.nil? || base.empty?

        home = ENV["XDG_DATA_HOME"] || File.join(Dir.home, ".local", "share")
        Pathname.new(File.join(home, "ricespace", "feeds"))
      end

      attr_reader :author, :dir

      def initialize(author, root: Feed.root)
        @author = author.to_s
        @dir = Pathname.new(root.to_s).join(@author)
      end

      def records
        return [] unless @dir.directory?

        @dir.children.select { |child| child.file? && child.extname == ".json" }
          .sort.map { |file| Record.from_hash(JSON.parse(file.read)) }
      rescue JSON::ParserError => error
        raise Error, "a feed file is damaged (#{error.message})"
      end

      def verify
        Record.verify_chain(records)
      end

      def head
        list = records
        list.empty? ? nil : list.max_by { |record| record["seq"] }
      end

      def next_seq
        (head&.fetch("seq", 0) || 0) + 1
      end

      def prev_hash
        current = head
        current ? Record.hash_of(current) : Record::GENESIS_PREV
      end

      # Append a signed record. The checks are the chain's, not the caller's:
      # seq must follow, prev must match, the signature must verify, the signer
      # must be allowed. Anything else is refused before it touches disk.
      def append(record)
        record = Record.from_hash(record)
        raise ChainError, "this feed is #{@author[0, 12]}, not #{record["author"][0, 12]}" unless record["author"] == @author

        trial = Record.verify_chain(records + [ record ])
        raise ChainError, trial.errors.first unless trial.ok?

        @dir.mkpath
        file = @dir.join(format("%08d.json", record["seq"]))
        raise ChainError, "seq #{record["seq"]} is already here" if file.file?

        temp = Pathname.new("#{file}.new")
        temp.write(JSON.pretty_generate(record) + "\n")
        temp.rename(file)
        record
      end

      # Import records from elsewhere (sync, sneakernet): same checks, order-free.
      # Returns how many were new.
      def merge(incoming)
        known = records.map { |record| Record.hash_of(record) }.to_h { |hash| [ hash, true ] }
        fresh = Array(incoming).map { |record| Record.from_hash(record) }
          .reject { |record| known[Record.hash_of(record)] }
          .sort_by { |record| record["seq"] }

        added = 0
        fresh.each do |record|
          begin
            append(record)
            added += 1
          rescue ChainError
            # A record that does not fit this chain is somebody else's problem —
            # a fork, a gap, or a forgery. It is skipped, not trusted.
            next
          end
        end
        added
      end
    end
  end
end
