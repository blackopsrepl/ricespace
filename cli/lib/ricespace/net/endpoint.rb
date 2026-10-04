# frozen_string_literal: true

require "json"

module RiceSpace
  module P2p
    module Net
      # One device's endpoint slot: where to dial it, signed by the device
      # itself so the master stays offline. Stored as a BEP44 mutable value
      # (bencoded, under 1000 bytes); verified against feed history every
      # time, everywhere — never trusted on signature alone.
      module Endpoint
        FORMAT = 2
        TTL = 7200
        CLOCK_SKEW = 600
        MAX_ADDRS = 4
        MAX_RELAYS = 2
        MAX_RV = 2
        # The publisher's own NAT verdict. Used by the ladder to decide
        # whether simultaneous-open is worth attempting — never trusted as
        # proof of anything.
        NAT_LABELS = %w[open mapped eim sym out unknown].freeze
        # A rendezvous ticket: relay addr + 64-bit secret + the feed waiting
        # on the other side. Tickets are single-use and expire with the slot.
        TICKET_BYTES = 8

        def self.build(node:, device:, addrs:, relay: [], rv: [], nat: "unknown",
            ticket: nil, at: Time.now.to_i, sign_with:)
          clean_addrs = Array(addrs).map(&:to_s).uniq
          clean_relays = Array(relay).map(&:to_s).uniq
          clean_rv = Array(rv).map(&:to_s).uniq
          if clean_addrs.size > MAX_ADDRS || clean_relays.size > MAX_RELAYS || clean_rv.size > MAX_RV
            raise Error, "too many endpoint addresses"
          end
          clean_addrs.each { |addr| check_addr!(addr) }
          clean_relays.each { |addr| check_addr!(addr) }
          clean_rv.each { |addr| check_addr!(addr) }
          label = nat.to_s
          raise Error, "unknown NAT label #{label.inspect}" unless NAT_LABELS.include?(label)
          unless ticket.nil?
            raise Error, "a ticket names a relay, a secret and a peer" unless
              ticket.is_a?(Hash) && ticket["relay"].is_a?(String) &&
              ticket["secret"].to_s.match?(/\A[0-9a-f]{16}\z/) &&
              Keys.valid_public?(ticket["peer"].to_s)
          end

          body = {
            "ep" => FORMAT, "node" => node.to_s.downcase, "device" => device.to_s.downcase,
            "addrs" => clean_addrs, "at" => at.to_i, "exp" => at.to_i + TTL, "relay" => clean_relays,
            "nat" => label, "rv" => clean_rv
          }
          body["ticket"] = { "relay" => ticket["relay"], "secret" => ticket["secret"].downcase,
            "peer" => ticket["peer"].downcase } unless ticket.nil?
          bytes = Canonical.signing_bytes(author: body["node"], seq: body["at"],
            prev: body["device"], kind: "endpoint", body: body.reject { |key, _| key == "sig" })
          body.merge("sig" => Keys.sign(sign_with, bytes))
        end

        # The slot payload as stored: bencoded with sorted keys, so the bytes
        # any DHT node holds are deterministic.
        def self.pack(record)
          Bencode.encode(record.transform_keys(&:to_s))
        end

        def self.unpack(packed)
          value = Bencode.decode(packed.b)
          raise Error, "not an endpoint slot" unless value.is_a?(Hash)

          value.transform_keys { |key| key.to_s.encode(Encoding::UTF_8) }
        rescue Error
          raise
        rescue StandardError
          raise Error, "not an endpoint slot"
        end

        # Verify a slot fetched from the DHT or gossip. `chain` is the held
        # feed's verify_chain result (or nil on first contact — then only the
        # signature checks run, and the caller pins provisionally). Returns
        # the record, or raises.
        def self.verify(record, chain: nil, now: Time.now.to_i)
          record = record.transform_keys(&:to_s)
          # Format 1 slots (no nat/rv) verify with defaults; anything else
          # unknown is dropped, not upgraded.
          raise Error, "unknown endpoint format" unless [ 1, FORMAT ].include?(record["ep"])
          raise Error, "not an account" unless Keys.valid_public?(record["node"].to_s)
          raise Error, "not a device key" unless Keys.valid_public?(record["device"].to_s)

          at = record["at"].to_i
          raise Error, "stale endpoint (expired)" unless record["exp"].to_i > now
          raise Error, "stale endpoint (clock skew)" if (now - at).abs > CLOCK_SKEW + TTL

          body = record.reject { |key, _| key == "sig" }
          bytes = Canonical.signing_bytes(author: record["node"], seq: at,
            prev: record["device"], kind: "endpoint", body: body)
          raise Error, "endpoint signature does not verify" unless Keys.verify(record["device"], record["sig"], bytes)

          addrs = Array(record["addrs"]).map(&:to_s)
          relays = Array(record["relay"]).map(&:to_s)
          rvs = Array(record["rv"]).map(&:to_s)
          raise Error, "too many endpoint addresses" if addrs.size > MAX_ADDRS || relays.size > MAX_RELAYS
          raise Error, "too many rendezvous relays" if rvs.size > MAX_RV

          addrs.each { |addr| check_addr!(addr) }
          relays.each { |addr| check_addr!(addr) }
          rvs.each { |addr| check_addr!(addr) }
          label = record["nat"].to_s
          label = "unknown" if label.empty? && record["ep"] == 1
          raise Error, "unknown NAT label #{label.inspect}" unless NAT_LABELS.include?(label)
          ticket = check_ticket!(record["ticket"]) unless record["ticket"].nil?

          # Authorisation, not just authentication: the slot's device must
          # belong to the feed it claims, at publication time. First contact
          # (no chain) skips this — the caller pins provisionally and the
          # feed records still have to verify against the out-of-band master.
          authorised!(record, chain, at) unless chain.nil?

          out = record.merge("addrs" => addrs, "relay" => relays, "nat" => label, "rv" => rvs)
          out["ticket"] = ticket unless ticket.nil?
          out
        end

        def self.check_ticket!(ticket)
          raise Error, "bad rendezvous ticket" unless ticket.is_a?(Hash)
          ticket = ticket.transform_keys(&:to_s)
          check_addr!(ticket["relay"].to_s)
          unless ticket["secret"].to_s.match?(/\A[0-9a-f]{16}\z/) &&
              Keys.valid_public?(ticket["peer"].to_s)
            raise Error, "bad rendezvous ticket"
          end

          { "relay" => ticket["relay"].to_s, "secret" => ticket["secret"].downcase,
            "peer" => ticket["peer"].downcase }
        end
        private_class_method :check_ticket!

        def self.authorised!(record, chain, at)
          raise Error, "endpoint feed is not verified" unless chain.ok?

          node = record["node"].to_s.downcase
          device = record["device"].to_s.downcase
          return if device == node || device == chain.state["owner"].to_s.downcase

          devices = chain.state["devices"]
          entry = devices[device]
          if entry.nil? || !entry["added"]
            raise Error, "endpoint device is not authorised on this feed"
          end
          if entry["revoked"] && !entry["cutoff"].nil? && at >= entry["cutoff"].to_i
            raise Error, "endpoint device was revoked before publication"
          end

          cutoff = chain.state["revocations"][device]
          raise Error, "endpoint device was revoked before publication" if cutoff && at > cutoff.to_i
        end
        private_class_method :authorised!

        def self.check_addr!(addr)
          host, port = addr.to_s.split(":", 2)
          raise Error, "bad endpoint address #{addr.inspect}" if host.nil? || port.nil?
          raise Error, "bad endpoint address #{addr.inspect}" if host.empty? || host == "0.0.0.0"

          port = Integer(port, 10)
          raise Error, "bad endpoint address #{addr.inspect}" unless (1..65535).cover?(port)
          raise Error, "bad endpoint address #{addr.inspect}" if host.include?(":") || host.include?(" ")
        rescue ArgumentError
          raise Error, "bad endpoint address #{addr.inspect}"
        end
        private_class_method :check_addr!

        # Off-LAN dial guard: private-range addrs from a remote slot are
        # somebody else's LAN, never a dial candidate from here.
        def self.lan_only?(addr)
          host = addr.to_s.split(":").first.to_s
          return true if host == "localhost"
          return false unless host.match?(/\A\d+\.\d+\.\d+\.\d+\z/)

          first, second = host.split(".").map(&:to_i)
          first == 10 || (first == 172 && (16..31).cover?(second)) ||
            (first == 192 && second == 168) || first == 127
        rescue StandardError
          false
        end
      end
    end
  end
end
