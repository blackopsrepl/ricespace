# frozen_string_literal: true

require "openssl"
require "io/console"

module RiceSpace
  module P2p
    # Ed25519 identities. One fact decides everything here: the account IS the
    # keypair, so this file is the account system. Stdlib only — OpenSSL owns the
    # curve, this module owns the shapes around it.
    #
    # At rest a private key is an AES-256-CBC encrypted PEM (0600), never raw hex.
    # In memory it is 32 raw bytes. On the wire it is 64 hex characters of public.
    module Keys
      CURVE = "ED25519"
      # Kept for reading old envelopes. Nothing new is written in this format.
      CIPHER = "AES-256-CBC"
      PUBLIC_HEX_LENGTH = 64
      PRIVATE_HEX_LENGTH = 64
      SIGNATURE_HEX_LENGTH = 128

      def self.generate
        key = OpenSSL::PKey.generate_key(CURVE)
        { private_hex: to_hex(key.raw_private_key), public_hex: to_hex(key.raw_public_key) }
      end

      def self.public_from_private(private_hex)
        key = OpenSSL::PKey.new_raw_private_key(CURVE, from_hex(private_hex, PRIVATE_HEX_LENGTH, "private key"))
        to_hex(key.raw_public_key)
      end

      # scrypt + AES-256-GCM envelope for disk. A blank passphrase is refused —
      # an unencrypted secret on disk is the theft this whole design exists to
      # stop, full-disk encryption or not.
      def self.protect(private_hex, passphrase)
        protect_v2(private_hex, passphrase)
      end

      # Passphrase quality floor: length + variety. Advisory — the caller
      # decides whether to refuse, because a device key on a machine the owner
      # physically holds is a different threat than a master.
      def self.passphrase_advice(passphrase)
        password = passphrase.to_s
        return "a passphrase is required" if password.empty?
        return "use at least 20 characters" if password.length < 20

        classes = [ /[a-z]/, /[A-Z]/, /[0-9]/, /[^a-zA-Z0-9]/ ].count { |pattern| password.match?(pattern) }
        return "mix upper, lower, digits and symbols" if classes < 3

        nil
      end

      def self.unprotect(pem, passphrase)
        payload = pem.to_s
        # v2 envelopes first; the old PEM format reads back for migration.
        if payload.lstrip.start_with?("{")
          begin
            return unprotect_v2(payload, passphrase)
          rescue CryptoError
            raise
          rescue StandardError
            nil
          end
        end

        key = OpenSSL::PKey.read(payload, passphrase.to_s)
        raise CryptoError, "not an #{CURVE} key" unless key.raw_private_key&.bytesize == 32

        to_hex(key.raw_private_key)
      rescue OpenSSL::PKey::PKeyError, ArgumentError => error
        raise CryptoError, "could not unlock the key (#{error.message})"
      end

      def self.sign(private_hex, bytes)
        raw = from_hex(private_hex, PRIVATE_HEX_LENGTH, "private key")
        key = OpenSSL::PKey.new_raw_private_key(CURVE, raw)
        to_hex(key.sign(nil, bytes.to_s))
      end

      def self.verify(public_hex, signature_hex, bytes)
        raw_pub = from_hex(public_hex, PUBLIC_HEX_LENGTH, "public key")
        raw_sig = from_hex(signature_hex, SIGNATURE_HEX_LENGTH, "signature")
        key = OpenSSL::PKey.new_raw_public_key(CURVE, raw_pub)
        key.verify(nil, raw_sig, bytes.to_s)
      rescue OpenSSL::PKey::PKeyError, ArgumentError
        false
      end

      def self.valid_public?(value)
        value.is_a?(String) && value.match?(/\A[0-9a-f]{#{PUBLIC_HEX_LENGTH}}\z/)
      end

      def self.ask_passphrase(prompt)
        $stderr.print "#{prompt}: "
        result = begin
          $stdin.noecho(&:gets)
        rescue StandardError
          $stdin.gets
        end
        $stderr.puts
        result.to_s.chomp
      end

      def self.to_hex(bytes)
        bytes.to_s.unpack1("H*")
      end

      def self.from_hex(value, length, label)
        unless value.is_a?(String) && value.match?(/\A[0-9a-f]{#{length}}\z/i)
          raise CryptoError, "not a #{label}"
        end

        [ value.downcase ].pack("H*")
      end

      # scrypt envelope for secrets at rest: salt + AES-256-GCM, one JSON
      # object. The old PEM format (MD5, single iteration) reads back through
      # `unprotect` for migration, but nothing new is written in it.
      SCRYPT_N = 2**15
      SCRYPT_R = 8
      SCRYPT_P = 1
      SCRYPT_DKLEN = 32
      GCM_IV_LEN = 12

      def self.protect_v2(private_hex, passphrase)
        password = passphrase.to_s
        raise CryptoError, "a passphrase is required" if password.empty?

        raw = from_hex(private_hex, PRIVATE_HEX_LENGTH, "private key")
        salt = Random.bytes(16)
        key = OpenSSL::KDF.scrypt(password, salt: salt, N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P, length: SCRYPT_DKLEN)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        iv = cipher.random_iv
        cipher.auth_data = "ricespace-p2p-v2"
        encrypted = cipher.update(raw) + cipher.final
        tag = cipher.auth_tag
        JSON.generate({
          "v" => 2, "kdf" => "scrypt", "n" => SCRYPT_N, "r" => SCRYPT_R, "p" => SCRYPT_P,
          "salt" => to_hex(salt), "iv" => to_hex(iv), "tag" => to_hex(tag),
          "data" => to_hex(encrypted)
        })
      end

      def self.unprotect_v2(payload, passphrase)
        data = payload.is_a?(String) ? JSON.parse(payload) : payload
        raise CryptoError, "not a v2 envelope" unless data.is_a?(Hash) && data["v"] == 2

        password = passphrase.to_s
        key = OpenSSL::KDF.scrypt(password,
          salt: [ data["salt"] ].pack("H*"), N: data["n"].to_i, r: data["r"].to_i,
          p: data["p"].to_i, length: SCRYPT_DKLEN)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = [ data["iv"] ].pack("H*")
        cipher.auth_tag = [ data["tag"] ].pack("H*")
        cipher.auth_data = "ricespace-p2p-v2"
        raw = cipher.update([ data["data"] ].pack("H*")) + cipher.final
        raise CryptoError, "not an #{CURVE} key" unless raw.bytesize == 32

        to_hex(raw)
      rescue JSON::ParserError, OpenSSL::Cipher::CipherError, ArgumentError => error
        raise CryptoError, "could not unlock the key (#{error.message})"
      end
    end
  end
end
