# frozen_string_literal: true

require "openssl"
require "socket"

module RiceSpace
  module P2p
    # TLS with key-pinning instead of certificate authorities. Both sides
    # present ephemeral self-signed Ed25519 certs minted from their device
    # keys; each side checks the other's cert public key is one it knows
    # (own key, a followed feed key, or an authorized device on a held feed).
    # No CA, no TOFU prompt — a stranger's cert fails closed.
    module Tls
      # A self-signed cert binding this device key, minted fresh per process.
      # Ephemeral by design: nothing to rotate, nothing to revoke, nothing on
      # disk. The signature is the trust — the cert is only TLS's envelope.
      def self.server_context(private_hex)
        raw = Keys.from_hex(private_hex, Keys::PRIVATE_HEX_LENGTH, "private key")
        key = OpenSSL::PKey.new_raw_private_key(Keys::CURVE, raw)
        pub = OpenSSL::PKey.new_raw_public_key(Keys::CURVE, key.raw_public_key)

        cert = OpenSSL::X509::Certificate.new
        cert.version = 2
        cert.serial = Random.rand(2**63)
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=ricespace-p2p")
        cert.public_key = pub
        cert.not_before = Time.now - 3600
        cert.not_after = Time.now + 24 * 3600
        cert.sign(key, nil)

        ctx = OpenSSL::SSL::SSLContext.new
        ctx.cert = cert
        ctx.key = key
        ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
        ctx.verify_callback = ->(_ok, _store) { true }
        ctx
      end

      def self.client_context(private_hex)
        ctx = server_context(private_hex)
        ctx.verify_mode = OpenSSL::SSL::VERIFY_PEER
        ctx
      end

      # The device public key inside a peer's presented cert.
      def self.peer_key(ssl_socket)
        cert = ssl_socket.peer_cert
        raise Error, "the peer showed no certificate" if cert.nil?

        raw = cert.public_key.raw_public_key
        raise Error, "the peer's certificate is not Ed25519" unless raw&.bytesize == 32

        raw.unpack1("H*")
      rescue OpenSSL::PKey::PKeyError, NoMethodError => error
        raise Error, "the peer's certificate is unusable (#{error.message})"
      end

      # Fail closed: the presented key must be our own device, a followed feed
      # key, or a device authorized on a feed we hold. Anything else is a
      # stranger, however valid its self-signature.
      def self.known_key?(presented_hex, identity:, peers:, store_root: Feed.root)
        ours = [ identity.master_public, identity.device_public ]
        return true if ours.include?(presented_hex)
        return true if peers.follow?(presented_hex)

        root = Pathname.new(store_root.to_s)
        return false unless root.directory?

        root.children.select(&:directory?).any? do |dir|
          feed = Feed.new(dir.basename.to_s, root: store_root)
          result = feed.verify
          next false unless result.ok?

          devices = result.state["devices"]
          devices.key?(presented_hex) && devices[presented_hex]["added"]
        end
      end
    end
  end
end
