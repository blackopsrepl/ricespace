# frozen_string_literal: true

module RiceSpace
  module P2p
    # One signed record in somebody's feed. Every record carries who wrote it
    # (author = the master key), which device signed it, its place in the chain
    # (seq + prev), what it says (kind + body), and the signature over all of it.
    #
    # Two rules decide everything here. Only the feed's owner appends — a record
    # from anybody else about this feed is forgery, not content. And history is
    # append-only: an edit is a new record, never a rewrite, so any friend holding
    # an old version can prove a rewritten one is a fork.
    module Record
      GENESIS_PREV = "0" * 64
      HASH_HEX_LENGTH = 64

      # Every kind of thing a feed can say. The first six are the page; reaction,
      # comment and friend are what other people said about one; the last five are
      # the account managing itself.
      KINDS = %w[
        page rice lists assets reaction comment friend
        device-add device-revoke rotation revocation tombstone recovery
      ].freeze

      OPINIONS = %w[like dislike none].freeze
      ASSET_KINDS = %w[shot build picture].freeze
      FRIEND_ACTIONS = %w[add remove].freeze

      # Ceilings that mirror the site's own, so a signed page and a stored page
      # cannot disagree about what fits: Profile::MAX_DOCUMENT_LENGTH,
      # Comment::MAX_BODY_LENGTH, and the showcase's line lengths.
      DOCUMENT_MAX = 200_000
      COMMENT_MAX = 1_000
      LINE_MAX = 80
      DETAILS_MAX = 20_000

      # How long a friend must have been on the list before their signature counts
      # toward a recovery. A v0 heuristic, stated plainly: keys added during the
      # attack itself cannot vote unless the attack spans this many of the owner's
      # own records. It raises the cost of sock-stuffing; it does not eliminate it.
      RECOVERY_TENURE = 5

      def self.build(author:, signer:, seq:, prev:, kind:, body:, sign_with:)
        raise ChainError, "a body is a hash" unless body.is_a?(Hash)

        record = {
          "author" => author.to_s, "signer" => signer.to_s,
          "seq" => seq.to_i, "prev" => prev.to_s,
          "kind" => kind.to_s, "body" => body
        }
        bytes = Canonical.signing_bytes(
          author: record["author"], seq: record["seq"], prev: record["prev"],
          kind: record["kind"], body: record["body"]
        )
        record["sig"] = Keys.sign(sign_with, bytes)
        check_shape!(record)
        record
      end

      def self.from_hash(hash)
        record = hash.is_a?(Hash) ? hash.transform_keys(&:to_s) : nil
        check_shape!(record || {})
        record
      end

      def self.hash_of(record)
        Canonical.record_hash(record)
      end

      def self.signing_bytes_of(record)
        Canonical.signing_bytes(
          author: record["author"], seq: record["seq"], prev: record["prev"],
          kind: record["kind"], body: record["body"]
        )
      end

      def self.signature_valid?(record)
        Keys.verify(record["signer"], record["sig"], signing_bytes_of(record))
      rescue CryptoError
        false
      end

      # Two records, same author and seq, different hashes: somebody — the owner or
      # a thief with the key — wrote history twice. The holder of the older copy
      # can prove it. Returns true when the pair is a fork.
      def self.fork?(first, second)
        first["author"] == second["author"] &&
          first["seq"] == second["seq"] &&
          hash_of(first) != hash_of(second)
      end

      def self.check_shape!(record)
        raise ChainError, "a record is a hash" unless record.is_a?(Hash)

        raise ChainError, "unknown author" unless Keys.valid_public?(record["author"])
        raise ChainError, "unknown signer" unless Keys.valid_public?(record["signer"])

        seq = record["seq"]
        raise ChainError, "seq starts at 1 and counts up" unless seq.is_a?(Integer) && seq >= 1

        prev = record["prev"].to_s
        if seq == 1
          raise ChainError, "the first record points at nothing" unless prev == GENESIS_PREV
        else
          raise ChainError, "prev is a record hash" unless prev.match?(/\A[0-9a-f]{#{HASH_HEX_LENGTH}}\z/)
        end

        kind = record["kind"].to_s
        raise ChainError, "unknown kind #{kind.inspect}" unless KINDS.include?(kind)
        raise ChainError, "a body is a hash" unless record["body"].is_a?(Hash)

        sig = record["sig"].to_s
        unless sig.match?(/\A[0-9a-f]{#{Keys::SIGNATURE_HEX_LENGTH}}\z/)
          raise ChainError, "a signature is 64 bytes of hex"
        end

        check_body!(kind, record["body"])

        # The record must survive its own serialisation: verify hashes every
        # record it walks, and a value outside plain JSON types would crash the
        # walk instead of failing it.
        begin
          Canonical.json(record)
        rescue Error
          raise ChainError, "a record is plain JSON types"
        end

        true
      end

      def self.check_body!(kind, body)
        case kind
        when "page"
          document = body["document"]
          raise ChainError, "a page carries its document" unless document.is_a?(String)
          raise ChainError, "a page is #{DOCUMENT_MAX} bytes at most" if document.bytesize > DOCUMENT_MAX
        when "rice"
          raise ChainError, "a rice carries facts" unless body.is_a?(Hash)
          %w[title summary].each do |field|
            value = body[field]
            next if value.nil?
            raise ChainError, "rice #{field} is a line" unless value.is_a?(String) && value.length <= 200
          end
          details = body["details"]
          if !details.nil? && (!details.is_a?(String) || details.bytesize > DETAILS_MAX)
            raise ChainError, "rice details are #{DETAILS_MAX} bytes at most"
          end
        when "lists"
          body.each do |list, entries|
            raise ChainError, "a list is an array" unless entries.is_a?(Array)
            raise ChainError, "unknown list #{list.inspect}" unless %w[blurbs demos builds links friends].include?(list.to_s)
          end
        when "assets"
          files = body["files"]
          raise ChainError, "assets name their files" unless files.is_a?(Array) && files.any?
          files.each do |file|
            raise ChainError, "an asset names its hash" unless file.is_a?(Hash) &&
              file["sha256"].to_s.match?(/\A[0-9a-f]{#{HASH_HEX_LENGTH}}\z/)
            raise ChainError, "an asset names its kind" unless ASSET_KINDS.include?(file["kind"].to_s)
          end
        when "reaction"
          raise ChainError, "a reaction names its feed" unless Keys.valid_public?(body["target_feed"])
          raise ChainError, "a reaction names its target" unless body["target_hash"].to_s.match?(/\A[0-9a-f]{#{HASH_HEX_LENGTH}}\z/)
          raise ChainError, "a reaction is like, dislike or none" unless OPINIONS.include?(body["opinion"].to_s)
        when "comment"
          text = body["text"]
          raise ChainError, "a comment is words" unless text.is_a?(String) && !text.strip.empty?
          raise ChainError, "a comment is #{COMMENT_MAX} characters at most" if text.length > COMMENT_MAX
          raise ChainError, "a comment answers something" unless body["parent_hash"].to_s.match?(/\A[0-9a-f]{#{HASH_HEX_LENGTH}}\z/)
        when "friend"
          raise ChainError, "a friend is an account" unless Keys.valid_public?(body["peer"])
          raise ChainError, "a friend is added or removed" unless FRIEND_ACTIONS.include?(body["action"].to_s)
          if body["action"].to_s == "add"
            petname = body["petname"]
            raise ChainError, "an added friend gets a petname" unless petname.is_a?(String) &&
              !petname.strip.empty? && petname.length <= 60
          end
        when "device-add"
          raise ChainError, "a device is a key" unless Keys.valid_public?(body["device"])
        when "device-revoke"
          raise ChainError, "a revocation names its device" unless Keys.valid_public?(body["device"])
          raise ChainError, "a revocation names its cutoff" unless body["cutoff_seq"].is_a?(Integer) && body["cutoff_seq"] >= 1
        when "rotation"
          raise ChainError, "a rotation names its successor" unless Keys.valid_public?(body["new_master"])
        when "revocation"
          raise ChainError, "a revocation names its subject" unless Keys.valid_public?(body["subject"])
          raise ChainError, "a revocation names its cutoff" unless body["cutoff_seq"].is_a?(Integer) && body["cutoff_seq"] >= 1
        when "tombstone"
          message = body["message"]
          if !message.nil? && (!message.is_a?(String) || message.length > 140)
            raise ChainError, "a goodbye is a line"
          end
        when "recovery"
          raise ChainError, "a recovery names its successor" unless Keys.valid_public?(body["new_master"])
          endorsements = body["endorsements"]
          raise ChainError, "a recovery carries its friends' signatures" unless endorsements.is_a?(Array) && endorsements.any?

          endorsements.each do |endorsement|
            raise ChainError, "an endorsement names its friend" unless endorsement.is_a?(Hash) &&
              Keys.valid_public?(endorsement["friend"])
            unless endorsement["sig"].to_s.match?(/\A[0-9a-f]{#{Keys::SIGNATURE_HEX_LENGTH}}\z/)
              raise ChainError, "an endorsement is signed"
            end
          end
        end
        true
      end

      # Walking a feed in order, checking every link holds: the signature, the
      # seq, the prev hash, and that the signer was allowed to sign at that seq.
      # Returns a Result: ok?, the errors, any forks found, and the state the
      # walk ended in (devices, friends, master, deleted).
      # ok? is false when anything is wrong OR when a fork was seen: a forked
      # feed is never clean, even when every record in it verifies on its own.
      # `state` carries the walk's end: author, owner, devices, friends (each a
      # petname plus the seq they joined at), revocations, deleted, seq, head.
      Result = Struct.new(:ok, :errors, :forks, :state) do
        def ok? = !!ok && forks.empty?
      end

      def self.verify_chain(records)
        errors = []
        forks = []
        state = {
          "author" => nil, "owner" => nil, "devices" => {}, "friends" => {},
          "revocations" => {}, "deleted" => false, "seq" => 0, "head" => GENESIS_PREV
        }

        ordered = Array(records).sort_by { |record| record["seq"].to_i }
        ordered.each do |record|
          begin
            check_shape!(record)
          rescue ChainError => error
            errors << "seq #{record["seq"].inspect}: #{error.message}"
            next
          end

          unless signature_valid?(record)
            errors << "seq #{record["seq"]}: the signature does not verify"
            next
          end

          # The feed's identity never changes: author is the key of seq 1, and
          # every later record names it. Rotation hands the *signing* to a new
          # key; it does not rename the feed.
          if state["author"].nil?
            state["author"] = record["author"]
            state["owner"] = record["author"]
          elsif record["author"] != state["author"]
            errors << "seq #{record["seq"]}: this feed is #{Canonical.short_id(state["author"])}"
            next
          end

          expected = state["seq"] + 1
          if record["seq"] != expected
            prior = ordered.select { |other| other["seq"] == record["seq"] && !other.equal?(record) }
            prior.each do |other|
              forks << { "seq" => record["seq"], "kept" => hash_of(other), "other" => hash_of(record) } if fork?(other, record)
            end
            errors << "seq #{record["seq"]}: expected #{expected}" if forks.empty?
            next
          end

          unless record["prev"] == state["head"]
            errors << "seq #{record["seq"]}: prev does not match seq #{state["seq"]}"
            next
          end

          if state["deleted"]
            errors << "seq #{record["seq"]}: the feed is closed — its goodbye is its last word"
            next
          end

          if record["kind"] == "recovery"
            unless recovery_well_formed?(state, record)
              errors << "seq #{record["seq"]}: a recovery is announced by its successor"
              next
            end
            unless recovery_accepted?(state, record)
              errors << "seq #{record["seq"]}: recovery needs its friends' signatures"
              next
            end
          else
            unless signer_allowed?(state, record)
              errors << "seq #{record["seq"]}: #{Canonical.short_id(record["signer"])} may not sign for this feed"
              next
            end

            unless kind_signed_by_owner?(state, record)
              errors << "seq #{record["seq"]}: #{record["kind"]} must be signed by the master key"
              next
            end

            if record["kind"] == "rotation" && record["body"]["new_master"] == state["owner"]
              errors << "seq #{record["seq"]}: a rotation moves forward"
              next
            end
          end

          apply!(state, record)
          state["seq"] = record["seq"]
          state["head"] = hash_of(record)
        end

        Result.new(errors.empty?, errors, forks, state)
      end

      # A signer may sign when it is the current owner, or a device that was
      # added before this seq and not revoked at or before it.
      def self.signer_allowed?(state, record)
        return true if record["signer"] == state["owner"]

        device = state["devices"][record["signer"]]
        return false if device.nil? || !device["added"]
        return false if device["revoked"] && record["seq"] >= device["cutoff"]

        cutoff = state["revocations"][record["signer"]]
        return false if cutoff && record["seq"] > cutoff

        true
      end

      # Account management is the owner's alone: devices, rotation and revocation
      # signed by a device key are the theft working, not the owner.
      def self.kind_signed_by_owner?(state, record)
        return true unless %w[device-add device-revoke rotation revocation].include?(record["kind"])

        record["signer"] == state["owner"]
      end

      # A recovery is announced by its own successor: the authoring key IS the
      # proposed new master, and that new master signs the record with itself.
      # Without this, the thief holding the old master could publish a "recovery"
      # to a key of their choosing and launder the theft through the mechanism.
      def self.recovery_well_formed?(state, record)
        record["signer"] == record["body"]["new_master"] &&
          record["body"]["new_master"] != state["owner"]
      end

      # A recovery hands the feed to a new key on the word of the owner's
      # friends: a majority of the current friends list, at least one, each
      # signing the announcement. The friends list is already on the feed, so any
      # verifier can check without asking anybody.
      #
      # Tenure matters: only friends added at least RECOVERY_TENURE of the
      # owner's own records ago may vote. A thief who stuffs the friends list
      # and immediately "recovers" gets no votes from their own sock keys — and
      # an owner who genuinely lost everything long ago keeps the friends who
      # have been there longest.
      def self.recovery_accepted?(state, record)
        friends = state["friends"]
        needed = [ friends.size / 2 + 1, 1 ].max
        body = { "new_master" => record["body"]["new_master"] }
        bytes = Canonical.signing_bytes(
          author: record["author"], seq: record["seq"], prev: record["prev"],
          kind: "recovery", body: body
        )
        distinct = Array(record["body"]["endorsements"]).select do |endorsement|
          next false unless endorsement.is_a?(Hash)

          friend = endorsement["friend"]
          joined = friends[friend]
          joined_at = joined.is_a?(Hash) ? joined["since"] : joined
          next false if !joined_at.is_a?(Integer)
          next false if record["seq"] - joined_at < RECOVERY_TENURE

          Keys.verify(friend, endorsement["sig"], bytes)
        end.map { |endorsement| endorsement["friend"] }.uniq

        distinct.size >= needed
      end

      def self.apply!(state, record)
        body = record["body"]
        case record["kind"]
        when "device-add"
          state["devices"][body["device"]] = { "added" => true, "revoked" => false, "cutoff" => nil }
        when "device-revoke"
          device = state["devices"][body["device"]] || { "added" => false }
          device["revoked"] = true
          device["cutoff"] = body["cutoff_seq"]
          state["devices"][body["device"]] = device
        when "rotation"
          state["owner"] = body["new_master"]
          state["devices"][body["new_master"]] = { "added" => true, "revoked" => false, "cutoff" => nil }
        when "revocation"
          state["revocations"][body["subject"]] = body["cutoff_seq"]
        when "recovery"
          state["owner"] = body["new_master"]
          state["devices"] = {}
          state["revocations"] = {}
        when "friend"
          if body["action"] == "add"
            state["friends"][body["peer"]] = { "petname" => body["petname"], "since" => record["seq"] }
          else
            state["friends"].delete(body["peer"])
          end
        when "lists"
          Array(body["friends"]).each do |entry|
            next unless entry.is_a?(Hash) && Keys.valid_public?(entry["peer"])

            state["friends"][entry["peer"]] = { "petname" => entry["petname"].to_s, "since" => record["seq"] }
          end
        when "tombstone"
          state["deleted"] = true
        end
      end
    end
  end
end
