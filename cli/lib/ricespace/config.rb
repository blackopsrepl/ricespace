# frozen_string_literal: true

require "json"
require "pathname"

module RiceSpace
  # What this machine remembers between runs: the space it speaks to and the token it speaks
  # with. The file is 0600, because one of those two things is a credential.
  module Config
    DIRECTORY = Pathname.new(ENV["RICESPACE_CONFIG_HOME"] || File.join(Dir.home, ".config", "ricespace"))

    class << self
      def path = DIRECTORY.join("config.json")

      # The saved configuration, or an empty one. A missing file is not an error — it is a
      # machine that has not been logged in yet, which every command reports on its own.
      def load
        file = path
        return {} unless file.file?

        parsed = JSON.parse(file.read)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      # Save the address and the token. Written and then moved into place, so a run that dies
      # mid-write cannot leave a truncated config behind — the next command would fail
      # somewhere far less obvious than here.
      def save(url:, token:)
        DIRECTORY.mkpath
        file = path
        temp = Pathname.new("#{file}.new")

        temp.write(JSON.generate({ "url" => url, "token" => token }) + "\n")
        temp.chmod(0o600)
        temp.rename(file)

        file
      end
    end
  end
end
