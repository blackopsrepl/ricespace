# frozen_string_literal: true

module RiceSpace
  module P2p
    # Petnames: your friends list maps a human name to a pubkey. Global
    # usernames are gone — `ron` is who YOU call ron, not a registry entry.
    # The UI shows `petname [a3f9..c1]`; same petname on two keys is a conflict
    # badge, never a merge.
    module Names
      def self.short(public_hex, length: 12)
        Canonical.short_id(public_hex.to_s)
      end

      def self.short_pair(public_hex)
        hex = public_hex.to_s
        "#{hex[0, 4]}..#{hex[-4, 4]}"
      end

      # petname -> pubkey, from a verify state (`state["friends"]` values carry
      # `{"petname"=>, "since"=>}`) or a plain map.
      def self.petnames(friends)
        friends.each_with_object({}) do |(pub, entry), acc|
          name = entry.is_a?(Hash) ? entry["petname"].to_s : entry.to_s
          next if name.empty?

          acc[name] ||= []
          acc[name] << pub
        end
      end

      # Names claimed by more than one key.
      def self.conflicts(friends)
        petnames(friends).select { |_name, pubs| pubs.uniq.size > 1 }
      end

      def self.resolve(petname, friends)
        friends.each do |pub, entry|
          name = entry.is_a?(Hash) ? entry["petname"].to_s : entry.to_s
          return pub if name == petname.to_s
        end
        nil
      end

      def self.display(petname, public_hex)
        "#{petname} [#{short_pair(public_hex)}]"
      end
    end
  end
end
