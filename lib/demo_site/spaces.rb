# frozen_string_literal: true

# Populating the demo accounts.
#
# The site is easier to understand with pages on it than with a directory of empties, so
# this writes a whole set of spaces: the three real ones (Ron, Vittorio, Cordelia) and a
# row of others that between them show every layout the site ships, plus two that wear no
# layout at all and write their own CSS by hand.
#
# It is written to be run more than once. Every part checks what is already there and only
# writes what is missing, so re-running it after adding a layout does not duplicate
# anybody's friends list or re-upload their screenshots.
#
# `bin/rails demo:populate` runs it. It is deliberately *not* part of `db:seeds`: seeding
# an install should give you a site with its owner account on it, not fifteen strangers.
module DemoSite
  # What the demo is: the accounts and their pages. The writer is separate because the
  # content is the part somebody will edit, and the code that applies it is not.
  module Spaces
    module_function

  # The three real accounts. These are the site's own people, so their pages are written
  # as pages rather than as filler.
  REAL = {
    "ron" => {
      name: "Ron",
      headline: "founder, and your first friend",
      mood: "based",
      greeting: "hey, thanks for adding me — i'm ron, i run the place",
      layout: nil # his own markup, in the site's own palette — see db/seeds.rb
    },
    "vittorio" => {
      name: "Vittorio",
      headline: "i build the thing i wanted in 2004",
      mood: "shipping",
      greeting: "this page is a test of the site, and the site is a test of the page"
    },
    "cordelia" => {
      name: "Cordelia",
      headline: "i write the parts that keep the rest honest",
      mood: "reading the diff",
      greeting: "everything here was written twice — once to work, once to be read"
    }
  }.freeze

  # Everybody else: one per theme the site ships, so the layout gallery has a page behind
  # it, plus two custom pages with no layout at all.
  OTHERS = [
    {
      username: "wes", name: "Wes", layout: "tokyo-night",
      headline: "blue hour, every hour",
      mood: "nocturnal",
      greeting: "the city at night is the best wallpaper there is",
      rice: { title: "winding road", summary: "the laptop i take everywhere.",
              hardware: "thinkpad x1", window_manager: "sway", bar: "waybar",
              terminal: "ghostty", font: "iosevka", theme: "tokyo night" },
      blurb: { title: "About", body: "i write at night and regret it in the morning." },
      demos: [ { title: "second reality", group_name: "Future Crew", party: "Assembly 93", release_year: 1993, ranking: 1,
                 url: "https://www.youtube.com/watch?v=rFjFRA0VS58", watch_note: "the one that started all of this" } ],
      build: { title: "the night machine", kind: "desktop", summary: "quiet, blue, on all night",
               specs: "ryzen 7, 32gb", cooling: "one big noctua" },
      tags: %w[quiet]
    },
    {
      username: "alice", name: "Alice", layout: "catppuccin",
      headline: "soft colours, sharp software",
      mood: "cosy",
      greeting: "everything is nicer in mauve",
      rice: { title: "pastel desk", summary: "a desk that matches the terminal.",
              hardware: "mac studio", window_manager: "aerospace", bar: "sketchybar",
              terminal: "wezterm", font: "jetbrains mono", theme: "catppuccin mocha" },
      blurb: { title: "About", body: "i design things, and then i build them, and then i redo the colours." },
      links: [ { platform: "youtube", url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "my desk tour" } ],
      build: { title: "the pastel tower", kind: "desktop", summary: "small, quiet, pink",
               specs: "m2 ultra, 64gb", cooling: "it is a mac" },
      tags: %w[cosy]
    },
    {
      username: "bob", name: "Bob", layout: "gruvbox",
      headline: "warm colours, cold beer",
      mood: "chilled",
      greeting: "if it isn't brown and orange i don't want it",
      rice: { title: "retro bench", summary: "the machine that looks like 1979.",
              hardware: "i7-4790k", window_manager: "i3", bar: "polybar",
              terminal: "alacritty", font: "terminus", theme: "gruvbox" },
      blurb: { title: "About", body: "i keep old hardware running because new hardware is boring." },
      demos: [ { title: "fr-025", group_name: "Farbrausch", party: "Breakpoint 2003", release_year: 2003, ranking: 1,
                 category: "64k intro", url: "https://www.youtube.com/watch?v=1hQmK4lV3sU" } ],
      build: { title: "the retro bench", kind: "desktop", summary: "a 2014 cpu in a 2026 case",
               specs: "i7-4790k, 16gb", cooling: "a fan from a skip" },
      tags: %w[warm]
    },
    {
      username: "carol", name: "Carol", layout: "everforest",
      headline: "green is a neutral",
      mood: "outside",
      greeting: "i touch grass, and then i come back and configure it",
      rice: { title: "forest floor", summary: "calm colours for long hours.",
              hardware: "framework 13", window_manager: "hyprland", bar: "waybar",
              terminal: "foot", font: "iosevka", theme: "everforest" },
      blurb: { title: "About", body: "linux on a laptop that was designed to run linux. imagine that." },
      build: { title: "the framework", kind: "laptop", summary: "repairable, green, mine",
               specs: "ryzen 7, 32gb", cooling: "whatever framework put in" },
      tags: %w[calm]
    },
    {
      username: "dave", name: "Dave", layout: "hackerman",
      headline: "it's not a phase, it's a colour scheme",
      mood: "wired",
      greeting: "GREEN TEXT ON BLACK. that's the post.",
      rice: { title: "the terminal", summary: "everything is a terminal if you try hard enough.",
              hardware: "some dell", window_manager: "sway", bar: "waybar",
              terminal: "kitty", font: "monospace", theme: "hackerman" },
      blurb: { title: "About", body: "i have read the man page. all of it." },
      demos: [ { title: "the matrix", group_name: "somebody", party: "a cinema", release_year: 1999, ranking: 3,
                 url: "https://www.youtube.com/watch?v=vKQi3bBA1y8" } ],
      build: { title: "the rig", kind: "desktop", summary: "green rgb, obviously",
               specs: "i9, 128gb", cooling: "water, because of course" },
      tags: %w[loud]
    },
    {
      username: "erin", name: "Erin", layout: "lumon",
      headline: "cold, corporate, exactly as designed",
      mood: "compliant",
      greeting: "please enjoy each page equally",
      rice: { title: "the severance floor", summary: "blue, quiet, and watched.",
              hardware: "a work laptop", window_manager: "gnome", bar: "none",
              terminal: "gnome-terminal", font: "cantarell", theme: "lumon" },
      blurb: { title: "About", body: "i do not remember writing this." },
      links: [ { platform: "youtube", url: "https://www.youtube.com/watch?v=x8H0j9FjO3c", title: "orientation" } ],
      build: { title: "the work machine", kind: "desktop", summary: "issued, not chosen",
               specs: "unknown", cooling: "please do not open it" },
      tags: %w[quiet]
    },
    {
      username: "frank", name: "Frank", layout: "miasma",
      headline: "swamp colours, dry humour",
      mood: "damp",
      greeting: "olive is a colour and i will die on this hill",
      rice: { title: "the bog", summary: "low contrast, low light, low effort.",
              hardware: "old thinkpad", window_manager: "dwm", bar: "none",
              terminal: "st", font: "terminus", theme: "miasma" },
      blurb: { title: "About", body: "dwm. no bar. no icons. no problem." },
      build: { title: "the bog machine", kind: "laptop", summary: "it boots, that's the spec",
               specs: "i5, 8gb", cooling: "the fan is a suggestion" },
      tags: %w[quiet]
    },
    {
      username: "grace", name: "Grace", layout: "ethereal",
      headline: "indigo, gold, and slightly on fire",
      mood: "luminous",
      greeting: "i like a page that looks like it's glowing from inside",
      rice: { title: "cosmic", summary: "the one that looks like a night sky.",
              hardware: "custom loop", window_manager: "hyprland", bar: "waybar",
              terminal: "ghostty", font: "iosevka", theme: "ethereal" },
      blurb: { title: "About", body: "a page should look like something. that's the whole idea." },
      demos: [ { title: "state of the art", group_name: "Spaceballs", party: "The Gathering 2004", release_year: 2004, ranking: 1,
                 url: "https://www.youtube.com/watch?v=FhL5ZtJUvZc" } ],
      build: { title: "the loop", kind: "desktop", summary: "hardline, because it looks right",
               specs: "7950x, 64gb", cooling: "custom loop, hardline" },
      tags: %w[loud]
    },
    {
      # No layout: every rule below is written on the page.
      username: "heidi", name: "Heidi", layout: nil, custom: :geocities,
      headline: "i miss when pages were pages",
      mood: "1998",
      greeting: "THIS PAGE IS UNDER CONSTRUCTION",
      rice: { title: "the bedroom pc", summary: "beige, loud, mine.",
              hardware: "pentium iii", window_manager: "none", bar: "taskbar",
              terminal: "cmd", font: "comic sans", theme: "windows 98" },
      blurbs: [
        { title: "About Me", body: "<b>hi!!</b> i like computers, my cat, and the <i>internet</i>." },
        { title: "My Cat", body: "his name is <b>modem</b> because he makes a noise when he wants food." }
      ],
      links: [ { platform: "youtube", url: "https://www.youtube.com/watch?v=8ZcmTl_1ER8", title: "my favourite song" } ],
      build: { title: "the bedroom pc", kind: "desktop", summary: "it has a turbo button",
               specs: "pentium iii, 256mb", cooling: "two fans and a dream" },
      tags: %w[very-loud]
    },
    {
      # No layout either, and a different hand entirely.
      username: "mika", name: "Mika", layout: nil, custom: :brutalist,
      headline: "type is the interface",
      mood: "strict",
      greeting: "no decoration. the words are the page.",
      rice: { title: "the workbench", summary: "nothing on it that is not used.",
              hardware: "nuc", window_manager: "sway", bar: "none",
              terminal: "alacritty", font: "berkeley mono", theme: "greyscale" },
      blurb: { title: "Note", body: "a page that needs a stylesheet to be readable is a page that has failed." },
      build: { title: "the NUC", kind: "desktop", summary: "velcroed to the underside of the desk",
               specs: "i7, 32gb", cooling: "the desk" },
      tags: %w[quiet]
    }
  ].freeze

  # The two hand-written pages. A layout is a starting point; these are what somebody writes
  # when they would rather do it themselves, which is the thing the site is for.
  CUSTOM = {
    # The era's actual house style: tiled background, centred everything, a hit counter, and
    # a table because that is how you laid a page out in 1998.
    geocities: <<~HTML,
      <style>
        body {
          background-color: #000080;
          background-image: repeating-linear-gradient(45deg, #000080 0 8px, #0000a0 8px 16px);
          color: #ffff00;
          font-family: "Comic Sans MS", "Chalkboard SE", cursive;
          font-size: 14px;
          text-align: center;
        }
        #profile { margin: 24px auto; width: 640px; }
        #profile h1 { color: #ff00ff; text-shadow: 2px 2px #00ffff; font-size: 28px; }
        #profile table { margin: 16px auto; border: 3px ridge #00ff00; background-color: #000040; }
        #profile td { padding: 8px 14px; }
        .blink { color: #ff0000; font-weight: bold; }
        .counter { border: 2px inset #808080; background-color: #000; color: #0f0; padding: 2px 8px; font-family: monospace; }
      </style>
      <div id="profile">
        <h1>~*~ welcome 2 my page ~*~</h1>
        <p class="blink">&gt;&gt;&gt; UNDER CONSTRUCTION &lt;&lt;&lt;</p>
        <marquee scrollamount="8" behavior="alternate">thanks for visiting!!! sign my guestbook!!!</marquee>
        <table>
          <tr>
            <td>visitors:</td>
            <td><span class="counter">001337</span></td>
          </tr>
          <tr>
            <td>made with:</td>
            <td>notepad.exe</td>
          </tr>
        </table>
        <p>best viewed at 800x600 in netscape navigator</p>
      </div>
    HTML

    # The opposite argument, made in the same medium: no colour, no boxes, no decoration.
    brutalist: <<~HTML
      <style>
        body {
          background-color: #ffffff;
          color: #000000;
          font-family: "Berkeley Mono", "Iosevka", ui-monospace, monospace;
          font-size: 15px;
          line-height: 1.45;
        }
        #site-header, footer { display: none; }
        main { max-width: 34rem; padding: 3rem 2rem; }
        #profile { border-top: 4px solid #000; padding-top: 1rem; }
        #profile h1 { font-size: 2rem; font-weight: 700; letter-spacing: -0.02em; }
        #profile p { margin: 0.75rem 0; }
        #profile hr { border: 0; border-top: 1px solid #000; margin: 1.5rem 0; }
        .orangetext15 { text-transform: none; letter-spacing: 0; border-bottom: 1px solid #000; }
        #showcase, #demos, .blurb, .friendSpace, .comments, #hardware, #watch {
          border: 0; border-top: 1px solid #000; padding: 1rem 0; background: none;
        }
        .fact dt { color: #000; }
        .fact dd, .blurb-body, .comment-body, .rice-summary { color: #000; }
      </style>
      <div id="profile">
        <h1>the page</h1>
        <p>there is no theme here. there is a stylesheet with eleven rules in it, and i wrote all of them.</p>
        <hr>
        <p>i am not against colour. i am against colour as a substitute for a decision.</p>
      </div>
    HTML
  }.freeze

  # The comment wall: who wrote what on whose page. Signed in, with a name on every line —
  # that is the point of the wall, and a seeded site should show it working.
  WALL = [
    [ "ron", "cordelia", "the counter on the front page is the only number here and i intend to keep it that way." ],
    [ "ron", "vittorio", "you gave me a password file and a bench. it is a good bench." ],
    [ "vittorio", "cordelia", "you rewrote the same function three times. it is better though." ],
    [ "cordelia", "vittorio", "the third one passes the tests and the first two did not. that is the difference." ],
    [ "wes", "alice", "your colours are the reason i re-did mine at 2am." ],
    [ "alice", "wes", "and yours are the reason i did mine at 3am. we are even." ],
    [ "heidi", "bob", "the counter on your page is a lie, mine says 1337." ],
    [ "bob", "heidi", "mine is honest, i only have four visitors" ],
    [ "dave", "grace", "green text is objectively correct" ],
    [ "grace", "dave", "green text is a personality, which is different" ],
    [ "mika", "cordelia", "no theme, no colour, eleven rules. it is the best page on here." ],
    [ "erin", "ron", "the page is very blue" ],
    [ "ron", "erin", "the page is very blue" ]
  ].freeze
      # Ratings, so the front page's ranking has something in it and the like buttons have
      # a state to show. Deliberately mixed: one page is well liked, one is disagreed with,
      # and one has no opinion on it at all, because that is what a ranking looks like with
      # a handful of people on the site.
      RATINGS = [
        # wes: liked by plenty
        %w[wes alice 1], %w[wes bob 1], %w[wes carol 1], %w[wes dave 1], %w[wes grace 1],
        # grace: liked and disliked — a page people reacted to
        %w[grace dave 1], %w[grace heidi 1], %w[grace mika 1],
        %w[grace erin -1], %w[grace frank -1],
        # hackerman: mostly disliked
        %w[dave alice -1], %w[dave carol -1], %w[dave erin -1], %w[dave grace -1],
        %w[dave mika -1], %w[dave heidi 1],
        # the rest: a like each, so the directory is not one page deep
        %w[vittorio ron 1], %w[cordelia ron 1], %w[cordelia mika 1], %w[vittorio wes 1],
        %w[alice bob 1], %w[bob carol 1], %w[heidi frank 1], %w[erin dave 1],
        %w[mika cordelia 1], %w[carol dave 1], %w[frank mika 1]
      ].freeze
  end
end
