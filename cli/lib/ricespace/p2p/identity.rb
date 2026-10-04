# frozen_string_literal: true

require "json"
require "pathname"

module RiceSpace
  module P2p
    # Who this machine speaks for. The master key is the account; the device key
    # is what signs day to day. The master stays offline — paper, in practice —
    # and each workstation holds only its own device key plus the master's public
    # half. A stolen laptop costs one device, revoked with the master, not the
    # account.
    #
    # On disk this is JSON beside the existing config, because stdlib reads JSON
    # and the folder must never learn a second format:
    #   { "master_public": ..., "master_secret": <encrypted PEM, or null when offline>,
    #     "device_public": ..., "device_secret": <encrypted PEM>,
    #     "device_name": ..., "created_at": ... }
    class Identity
      FILENAME = "identity.json"

      attr_reader :master_public, :device_public, :device_name, :path

      def initialize(path:, master_public:, device_public:, device_name:)
        @path = path
        @master_public = master_public
        @device_public = device_public
        @device_name = device_name
      end

      def short_id = Canonical.short_id(master_public)

      def device?
        !@device_public.nil? && !@device_public.empty?
      end

      # A fresh account: master + first device, both secrets encrypted at rest.
      # A blank master passphrase is refused — the master is the account, and an
      # unencrypted master on disk is the theft this whole design exists to stop.
      def self.create(dir:, device_name:, master_passphrase:, device_passphrase: nil)
        raise Error, "name the device (this machine)" if device_name.to_s.strip.empty?
        raise Error, "the master key needs a passphrase" if master_passphrase.to_s.empty?

        master = Keys.generate
        device = Keys.generate

        data = {
          "master_public" => master[:public_hex],
          "master_secret" => Keys.protect(master[:private_hex], master_passphrase),
          "device_public" => device[:public_hex],
          "device_secret" => Keys.protect(device[:private_hex], device_passphrase || master_passphrase),
          "device_name" => device_name.to_s.strip,
          "created_at" => Time.now.utc.iso8601
        }
        write_file(dir, data)
        load(dir)
      end

      # A second workstation: it holds its own device key and only the master's
      # public half. Joining is a `device-add` record signed by the master.
      def self.join(dir:, device_name:, master_public:, device_passphrase:)
        keypair = Keys.generate
        data = {
          "master_public" => master_public.to_s,
          "master_secret" => nil,
          "device_public" => keypair[:public_hex],
          "device_secret" => Keys.protect(keypair[:private_hex], device_passphrase),
          "device_name" => device_name.to_s.strip,
          "created_at" => Time.now.utc.iso8601
        }
        write_file(dir, data)
        load(dir)
      end

      def self.load(dir)
        file = Pathname.new(dir.to_s).join(FILENAME)
        raise Error, "no identity here — run `ricespace identity create` first" unless file.file?

        data = JSON.parse(file.read)
        new(
          path: file,
          master_public: data["master_public"].to_s,
          device_public: data["device_public"].to_s,
          device_name: data["device_name"].to_s
        )
      rescue JSON::ParserError
        raise Error, "the identity file is damaged"
      end

      def self.exists?(dir)
        Pathname.new(dir.to_s).join(FILENAME).file?
      end

      # The device secret, decrypted. The one credential this machine signs with.
      def unlock_device(passphrase)
        data = JSON.parse(@path.read)
        secret = data["device_secret"]
        raise Error, "no device key on this machine" if secret.nil?

        Keys.unprotect(secret, passphrase)
      end

      # The master secret, decrypted. Only present on the machine that created
      # the account — or wherever the paper backup was restored. Used for
      # rotation, device add/revoke, and nothing else.
      def unlock_master(passphrase)
        data = JSON.parse(@path.read)
        secret = data["master_secret"]
        raise Error, "the master key is not on this machine" if secret.nil?

        private_hex = Keys.unprotect(secret, passphrase)
        actual = Keys.public_from_private(private_hex)
        raise Error, "the master key does not match" unless actual == @master_public

        private_hex
      end

      # The offline backup: master public + master secret, printed once for paper.
      def backup(passphrase)
        private_hex = unlock_master(passphrase)
        { "master_public" => @master_public, "master_secret" => private_hex }
      end

      def self.write_file(dir, data)
        root = Pathname.new(dir.to_s)
        root.mkpath
        file = root.join(FILENAME)
        temp = Pathname.new("#{file}.new")
        temp.write(JSON.generate(data) + "\n")
        temp.chmod(0o600)
        temp.rename(file)
        file
      end
      private_class_method :write_file
    end
  end
end
