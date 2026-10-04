# frozen_string_literal: true

require "pathname"
require "fileutils"

module RiceSpace
  module P2p
    # Pictures by content hash. A replicated body names `sha256`; this is where
    # the bytes live. Local policy decides how much of others we keep — the
    # cap is enforced at fetch time, not at rest.
    module Assets
      def self.root(store_root = Feed.root)
        Pathname.new(store_root.to_s).join("assets")
      end

      def self.put(bytes, store_root = Feed.root)
        digest = Canonical.digest(bytes)
        dir = root(store_root)
        dir.mkpath
        file = dir.join(digest)
        unless file.file?
          temp = Pathname.new("#{file}.new")
          temp.binwrite(bytes.to_s)
          temp.rename(file)
        end
        digest
      end

      def self.put_file(path, store_root = Feed.root)
        put(Pathname.new(path.to_s).binread, store_root)
      end

      def self.get(sha256, store_root = Feed.root)
        file = root(store_root).join(sha256.to_s)
        return nil unless file.file?

        file.binread
      end

      def self.have?(sha256, store_root = Feed.root)
        root(store_root).join(sha256.to_s).file?
      end

      def self.bytes_stored(store_root = Feed.root)
        dir = root(store_root)
        return 0 unless dir.directory?

        dir.children.select(&:file?).sum(&:size)
      end
    end
  end
end
