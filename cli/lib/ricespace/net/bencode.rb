# frozen_string_literal: true

module RiceSpace
  module P2p
    module Net
      # Bencode: the DHT's serialisation. ~40 lines, no gem — taking a
      # dependency for this would be dependency theatre. All strings ride as
      # binary (ASCII-8BIT): node ids and infohashes are not text, and a
      # UTF-8-typed decode would corrupt them.
      module Bencode
        def self.encode(value)
          case value
          when String
            raw = value.b
            "#{raw.bytesize}:#{raw}"
          when Integer then "i#{value}e"
          when Array then "l#{value.map { |entry| encode(entry) }.join}e"
          when Hash
            inner = value.map { |key, entry| [ key.to_s.b, entry ] }
              .sort_by(&:first)
              .map { |key, entry| encode(key) + encode(entry) }.join
            "d#{inner}e"
          else
            raise Error, "cannot bencode #{value.class.name}"
          end
        end

        def self.decode(bytes)
          raw = bytes.b
          value, rest = parse(raw, 0)
          raise Error, "trailing bytes after bencoded value" unless rest == raw.bytesize

          value
        end

        def self.parse(raw, at)
          token = raw.getbyte(at)
          raise Error, "truncated bencoded value" if token.nil?

          char = token.chr
          if char == "i"
            end_at = raw.index("e", at)
            raise Error, "truncated bencoded integer" if end_at.nil?

            [ Integer(raw[at + 1...end_at]), end_at + 1 ]
          elsif char == "l" || char == "d"
            parse_collection(raw, at, char)
          elsif char.match?(/\d/)
            colon = raw.index(":", at)
            raise Error, "truncated bencoded string" if colon.nil?

            length = Integer(raw[at...colon])
            start = colon + 1
            stop = start + length
            raise Error, "truncated bencoded string" if raw.bytesize < stop

            [ raw.byteslice(start, length), stop ]
          else
            raise Error, "invalid bencode token #{char.inspect}"
          end
        end
        private_class_method :parse

        def self.parse_collection(raw, at, kind)
          items = kind == "d" ? {} : []
          cursor = at + 1
          last_key = nil
          loop do
            raise Error, "truncated bencoded #{kind}" if cursor >= raw.bytesize
            break cursor += 1 if raw.getbyte(cursor).chr == "e"

            key_or_value, cursor = parse(raw, cursor)
            if kind == "d"
              raise Error, "a bencoded dict key is a string" unless key_or_value.is_a?(String)
              raise Error, "bencoded dict keys sort" if !last_key.nil? && key_or_value.b < last_key

              last_key = key_or_value.b
              # Keys are ASCII in KRPC; normalise so downstream dig/[] with
              # UTF-8 literals always hits. Values stay binary.
              key = key_or_value.ascii_only? ? key_or_value.dup.force_encoding(Encoding::UTF_8) : key_or_value
              value, cursor = parse(raw, cursor)
              items[key] = value
            else
              items << key_or_value
            end
          end
          [ items, cursor ]
        end
        private_class_method :parse_collection
      end
    end
  end
end
