# frozen_string_literal: true

require "json"
require "digest/sha2"

module RiceSpace
  module P2p
    # Something is wrong with a record, a key or a feed: malformed, badly signed,
    # or breaking the chain. Not a bug — a thing to be told about plainly.
    class Error < StandardError; end
    class CryptoError < Error; end
    class ChainError < Error; end

    # Canonical bytes: the one serialisation every signature is over.
    #
    # Hash keys sorted by their string form, no whitespace, UTF-8. Two records with
    # the same meaning have the same bytes on every machine, so a signature made on
    # one verifies on another — including one that arrived on a USB stick.
    module Canonical
      DOMAIN = "ricespace-p2p-v1"

      def self.json(value)
        JSON.generate(normalize(value))
      end

      def self.digest(bytes)
        Digest::SHA256.hexdigest(bytes.to_s)
      end

      def self.file_digest(path)
        Digest::SHA256.file(path.to_s).hexdigest
      end

      # The address of a record: the hash of its canonical form, signature included.
      def self.record_hash(record)
        digest(json(record))
      end

      # What a signature covers. Domain-separated so a signature can never be lifted
      # into another protocol that signs the same JSON.
      def self.signing_bytes(author:, seq:, prev:, kind:, body:)
        [ DOMAIN, author.to_s, seq.to_i.to_s, prev.to_s, kind.to_s, json(body) ].join("\x00")
      end

      # The short form of an account shown beside a petname: `rice:` plus 12 hex
      # characters (48 bits) of the master public key. Enough to tell follows apart;
      # the full key is one `identity show` away.
      def self.short_id(public_hex)
        "rice:#{public_hex.to_s[0, 12]}"
      end

      def self.normalize(value)
        case value
        when Hash
          value.each_with_object({}) { |(key, entry), acc| acc[key.to_s] = normalize(entry) }
            .sort_by(&:first).to_h
        when Array
          value.map { |entry| normalize(entry) }
        when String, Integer, Float, TrueClass, FalseClass, NilClass
          value
        when Symbol
          value.to_s
        else
          raise Error, "cannot canonicalise #{value.class.name}"
        end
      end
      private_class_method :normalize
    end
  end
end
