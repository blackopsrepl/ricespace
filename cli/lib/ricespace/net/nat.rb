# frozen_string_literal: true

module RiceSpace
  module P2p
    module Net
      # NAT characterisation: best-effort labels, always stating how each was
      # determined. A label is never proof of inbound reachability — only a
      # successful inbound dial proves that, and this module never claims one.
      module Nat
        Result = Struct.new(:label, :detail, :mapped_port, :external) do
          def to_h = { "label" => label, "detail" => detail, "mapped_port" => mapped_port, "external" => external }
        end

        # Probe in order: UPnP mapping → NAT-PMP mapping → STUN mapping
        # behaviour. Returns a Result; never raises (worst case: unknown).
        def self.characterise(port:, upnp: Upnp, natpmp: Natpmp, stun: Stun)
          mapped = try_upnp(port, upnp)
          return mapped unless mapped.nil?

          mapped = try_natpmp(port, natpmp)
          return mapped unless mapped.nil?

          observe(port, stun)
        end

        def self.try_upnp(port, upnp)
          locations = upnp.discover
          return nil if locations.empty?

          igd = locations.filter_map { |location| upnp.describe(location) }.first
          return Result.new("upnp-igw-no-mapping", "an IGD answered but no mapping was granted", nil, nil) if igd.nil?

          external = upnp.map(igd, internal_port: port)
          if external
            return Result.new("port-mapped", "UPnP IGD granted TCP #{external} → #{port} (lease, released on exit)",
              external, nil)
          end

          Result.new("upnp-igw-no-mapping", "an IGD answered but no mapping was granted", nil, nil)
        rescue Error
          nil
        end
        private_class_method :try_upnp

        def self.try_natpmp(port, natpmp)
          external = natpmp.map(internal_port: port)
          return nil if external.nil?

          Result.new("port-mapped", "NAT-PMP granted TCP #{external} → #{port} (lifetime, re-assert hourly)",
            external, nil)
        rescue Error
          nil
        end
        private_class_method :try_natpmp

        def self.observe(port, stun)
          first = stun.observe
          begin
            second = stun.observe(server: Stun::SERVERS[1][0], port: Stun::SERVERS[1][1])
          rescue Error
            return Result.new("outbound-only",
              "STUN observed #{first["host"]}:#{first["port"]} once; second server silent — " \
              "treat as outbound-only until a peer dials back", nil, first)
          end

          if first["host"] == second["host"] && first["port"] == second["port"]
            Result.new("endpoint-independent-mapping",
              "STUN observed #{first["host"]}:#{first["port"]} from two servers — " \
              "stable mapping, direct dial *may* work; unproven until a peer dials back",
              nil, first)
          else
            Result.new("symmetric-nat",
              "STUN observed different mappings per server (#{first["port"]} vs #{second["port"]}) — " \
              "direct dial unlikely; outbound sync and relay still work", nil, first)
          end
        rescue Error
          Result.new("unknown", "no IGD, no NAT-PMP, STUN silent — outbound sync may still work", nil, nil)
        end
        private_class_method :observe
      end
    end
  end
end
