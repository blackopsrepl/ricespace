# frozen_string_literal: true

# ricespace — a page per account, and the HTML and CSS to fill it.
# Copyright (C) 2026 Vittorio
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option) any
# later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

require_relative "ricespace/version"
require_relative "ricespace/ui"
require_relative "ricespace/space"
require_relative "ricespace/folder"
require_relative "ricespace/config"
require_relative "ricespace/completions"
require_relative "ricespace/p2p/canonical"
require_relative "ricespace/p2p/keys"
require_relative "ricespace/p2p/record"
require_relative "ricespace/p2p/identity"
require_relative "ricespace/p2p/feed"
require_relative "ricespace/p2p/assets"
require_relative "ricespace/p2p/names"
require_relative "ricespace/p2p/peers"
require_relative "ricespace/p2p/seeds"
require_relative "ricespace/p2p/tls"
require_relative "ricespace/p2p/address"
require_relative "ricespace/net/bencode"
require_relative "ricespace/net/dht"
require_relative "ricespace/net/endpoint"
require_relative "ricespace/net/stun"
require_relative "ricespace/net/upnp"
require_relative "ricespace/net/natpmp"
require_relative "ricespace/net/nat"
require_relative "ricespace/net/relay"
require_relative "ricespace/net/relays"
require_relative "ricespace/net/discovery"
require_relative "ricespace/p2p/sync"
require_relative "ricespace/command"

# The RiceSpace client library and command line.
#
# Three layers, and the split is the design:
#
#   Command  the surface — the commands, their flags and the words a person types.
#   Space    the client  — it knows the API, the error shape the server returns, and how a
#                         write is protected by a revision.
#   Ui       the output  — the site's own vocabulary, in a terminal.
#
# The API is the one a coding agent already uses, so nothing here is a second way into the
# data: it is the same way, typed by hand.
module RiceSpace
  # Everything the client raises, so a caller can catch one thing.
  class Error < StandardError; end

  # Something the person typed is wrong. Not a bug — a thing to be told about plainly.
  class UsageError < Error; end

  # The space answered, and said no. Carries the server's own code so the message can be
  # the server's message rather than a guess at it.
  class ApiError < Error
    attr_reader :code, :status

    def initialize(message, code: nil, status: nil)
      super(message)
      @code = code
      @status = status
    end
  end
end
