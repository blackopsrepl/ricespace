#!/usr/bin/env ruby
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

# Generate RiceSpace layouts from the Omarchy themes they are named after.
#
# The point of generating rather than hand-writing: a layout that claims to be Tokyo Night
# should use Tokyo Night's actual colours, and there are thirty-one of them in each theme's
# `colors.toml`. Hand-copying eight of those into eight files is how a palette drifts from
# the theme it is supposed to be.
#
# Omarchy itself is MIT licensed (Copyright (c) David Heinemeier Hansson), so reading its
# palettes is unencumbered; the wallpapers are referenced by URL rather than copied, and each
# layout credits the theme it came from.
#
# Run from a checkout of Omarchy:
#
#     tools/omarchy-layouts.rb ~/omarchy/themes app/layouts
#
# Nothing here needs Rails — it reads files and writes files, which is why it is a plain
# script rather than a rake task.

module OmarchyLayouts
  # The eight Omarchy leads its own manual with, in that order. There is no published
  # popularity ranking for themes, so "the popular ones" means the ones the project itself
  # presents first.
  THEMES = %w[
    tokyo-night catppuccin lumon ethereal everforest gruvbox miasma hackerman
  ].freeze

  # Each theme's own signature background, chosen by hand because the file names are
  # per-theme and the first alphabetically is not always the one the preview shows.
  WALLPAPER = {
    "tokyo-night" => "0-winding-road.webp",
    "catppuccin" => "1-totoro.webp",
    "lumon" => "01-united-in-severance.webp",
    "ethereal" => "1-cosmic.webp",
    "everforest" => "1-tree-tops.webp",
    "gruvbox" => "1-the-backwater.jpg",
    "miasma" => "01-nature-of-fear.webp",
    "hackerman" => "1-synth-scape.jpg"
  }.freeze

  RAW = "https://raw.githubusercontent.com/basecamp/omarchy/master/themes"

  # A theme's colours, read from its own colors.toml — the single source of truth.
  #
  # Hand-parsed rather than with a TOML library, because the file is a flat list of
  # `key = "value"` lines and a parser would be a dependency for a script that ships in a
  # repository people run by hand.
  def self.palette(theme_dir)
    text = File.read(File.join(theme_dir, "colors.toml"))
    text.scan(/^(\w+)\s*=\s*"([^"]+)"/).to_h
  end

  # One theme as a RiceSpace layout: its palette over the page's own anatomy.
  #
  # Every colour below is a value from that theme. Nothing here is chosen by eye, which is
  # the whole reason this file exists.
  def self.layout(theme, c)
    wall = "#{RAW}/#{theme}/backgrounds/#{WALLPAPER.fetch(theme)}"
    name = theme.split("-").map(&:capitalize).join(" ")

    # A theme without a `bright_magenta` (only some define it) falls back to `magenta`.
    bright_magenta = c["bright_magenta"] || c["magenta"]

    # A theme without an `orange` falls back to `yellow`.
    orange = c["orange"] || c["yellow"]

    <<~CSS
      /* name: #{name}
         author: Omarchy (#{theme})
         description: Generated from Omarchy's #{theme} palette — #{c["background"]} on the page,
         #{c["accent"]} for links, and the theme's own wallpaper behind it. */

      /* The theme's own background, fetched from the Omarchy repository. A wallpaper is
         half of what a theme looks like; a page wearing this one is wearing the desktop. */
      body {
        background-color: #{c["background"]};
        background-image: url(#{wall});
        background-size: cover;
        background-position: center;
        background-attachment: fixed;
        color: #{c["foreground"]};
        font-family: "Iosevka", "JetBrainsMono Nerd Font", monospace;
        font-size: 12px;
        line-height: 1.6;
      }

      /* The site's own chrome is part of what a theme restyles, so it goes. */
      #site-header, footer { display: none; }

      main {
        max-width: none;
        padding: 0;
        /* A scrim, not a wall: the theme's wallpaper is half of what the theme looks like,
           so the page tints it rather than covering it. The panels below are opaque, which
           is where the text lives. */
        background-color: color-mix(in srgb, #{c["darker_background"]} 45%, transparent);
        backdrop-filter: blur(1px);
        min-height: 100vh;
      }

      a, a:link, a:visited { color: #{c["accent"]}; text-decoration: none; }
      a:hover { color: #{c["bright_foreground"]}; background-color: #{c["selection"]}; }

      /* The name block: the theme's own card against its own wallpaper.
         In the flow rather than absolutely placed, so the page below it cannot collide
         with it however much markup the owner wrote. */
      .contactTable {
        margin: 32px auto 0;
        width: 820px;
        max-width: calc(100% - 32px);
        border: 1px solid #{c["accent"]};
        background-color: #{c["dark_background"]};
        padding: 20px 24px;
        box-shadow: 0 0 0 1px #{c["darker_background"]}, 0 18px 40px #{c["darker_background"]};
      }

      .profile-pic-default { border: 1px dashed #{c["muted"]}; color: #{c["dark_foreground"]}; }

      .nametext {
        color: #{c["bright_foreground"]};
        font-size: 26px;
        font-weight: 600;
        letter-spacing: 0.04em;
      }

      .greeting { color: #{c["foreground"]}; }
      .mood, .label { color: #{c["dark_foreground"]}; text-transform: uppercase; letter-spacing: 0.14em; font-size: 10px; }
      .username { color: #{c["cyan"]}; }

      /* Every section heading is the theme's accent, hairlined in its own muted shade. */
      .orangetext15 {
        color: #{c["accent"]};
        border-bottom: 1px solid #{c["muted"]};
        text-transform: uppercase;
        letter-spacing: 0.16em;
        font-size: 11px;
        padding-bottom: 6px;
      }

      /* Every part of a page is the same panel of the theme's surface: the rice, the
         markup the owner wrote, and all the rest. The markup is included because it is
         where a person writes, and a page whose text falls outside its own card is a
         layout that only looks right with the markup it was tested against. */
      #showcase, #profile, #demos, #hardware, #watch, .blurb, .friendSpace, .comments {
        margin: 18px auto;
        width: 820px;
        max-width: calc(100% - 32px);
        background-color: #{c["dark_background"]};
        border: 1px solid #{c["lighter_background"]};
        padding: 18px 24px;
        overflow-wrap: break-word;
      }

      /* A page's own markup keeps whatever it sets, but nothing of it may escape the
         panel by absolute positioning or run off the side. */
      #profile { position: relative; overflow: hidden; }

      .rice-title { color: #{c["yellow"]}; }
      .rice-summary { color: #{c["foreground"]}; }

      /* The facts the rice is made of, as the theme's own key/value pairs. */
      .fact { display: inline-block; margin: 0 18px 6px 0; }
      .fact dt { color: #{c["dark_foreground"]}; text-transform: uppercase; font-size: 10px; letter-spacing: 0.12em; }
      .fact dd { color: #{c["bright_foreground"]}; }

      .blurb-title { color: #{c["magenta"]}; }
      .blurb-body, #profile { color: #{c["foreground"]}; }
      #profile h1, #profile h2 { color: #{c["bright_foreground"]}; }

      .demo-title, .build-title { color: #{orange}; }
      .demo-credit, .build-details, .demo-placing { color: #{c["dark_foreground"]}; }

      .friendCount { color: #{c["dark_foreground"]}; }
      .friend, .top8 li { color: #{c["green"]}; }

      .comment { border-top: 1px solid #{c["lighter_background"]}; padding-top: 10px; margin-top: 10px; }
      .comment .nametext { color: #{c["cyan"]}; font-size: 13px; }
      .comment-body { color: #{c["foreground"]}; }

      .audio.player { border-left: 3px solid #{c["accent"]}; padding-left: 10px; }
      .audio.player a { color: #{bright_magenta}; }

      .rice-frame, .rice-shot { border: 1px solid #{c["muted"]}; }

      /* The theme's wordmark, from the theme itself, as the page's own mark. */
      #profile-stamp { color: #{c["dark_foreground"]}; }
    CSS
  end

  def self.run(themes_dir, out_dir, argv = ARGV.dup)
    themes = File.expand_path(themes_dir)
    out = File.expand_path(out_dir)

    unless File.directory?(themes)
      warn "not a directory: #{themes}"
      return 1
    end

    FileUtils.mkdir_p(out)

    THEMES.each do |theme|
      directory = File.join(themes, theme)
      unless File.directory?(directory)
        warn "missing theme: #{directory}"
        return 1
      end

      css = layout(theme, palette(directory))
      File.write(File.join(out, "#{theme}.css"), css)
      puts "wrote #{theme}.css (#{css.bytesize} bytes)"
    end

    0
  end

  def self.main(argv)
    if argv.length != 2
      puts "Generate RiceSpace layouts from the Omarchy themes they are named after."
      puts
      puts "    tools/omarchy-layouts.rb <omarchy/themes> <app/layouts>"
      return 2
    end

    run(argv[0], argv[1], argv)
  end
end

require "fileutils"

if $PROGRAM_NAME == __FILE__
  exit OmarchyLayouts.main(ARGV)
end
