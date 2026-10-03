# frozen_string_literal: true

require_relative "lib/ricespace/version"

Gem::Specification.new do |spec|
  spec.name = "ricespace"
  spec.version = RiceSpace::VERSION
  spec.authors = [ "Vittorio" ]
  spec.summary = "Your RiceSpace page, from the terminal you already live in."
  spec.description = <<~TEXT
    The RiceSpace client. It talks to your space over the same HTTP API an agent uses, with
    the same token: it shows your page and your rice, reads and writes your markup, sets the
    lists, rates somebody else's page, and keeps a folder on your own machine that is your
    space — clone it, edit it with your editor, preview it, push it back.
  TEXT
  spec.homepage = "https://github.com/blackopsrepl/ricespace"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 3.2"

  spec.files = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = [ "ricespace" ]
  spec.require_paths = [ "lib" ]

  # Nothing. The whole client is the standard library — net/http, json, optparse,
  # pathname — because a tool somebody installs to talk to their page should not bring a
  # dependency tree with it.
end
