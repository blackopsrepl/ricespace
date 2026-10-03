# RiceSpace

**A page per account, and the HTML and CSS to fill it.**

<img src="docs/assets/screens/home.png" alt="The RiceSpace front page: the most-reacted-to pages, then the directory" width="760">

You get a page, a screenshot of your setup — your *rice* — and the whole page is yours to
style. Not a form with a theme picker: real markup and a real stylesheet. Paste a layout from
2006, write your own CSS, put a `<marquee>` on it. If you lived through the era when your
profile page was the most interesting thing you owned, this is that, with a proper editor and
an API.

## Try it

    make setup     # install gems, prepare the database
    make serve     # http://localhost:3000

Then:

1. **Create a page** — pick a username, that becomes your address.
2. You land in the **studio**. Write your markup and stylesheet; save is instant.
3. Add your **rice** — a screenshot of your desktop, and what is in it.
4. Fill in the rest: a picture, blurbs, a song, friends, videos, demos, hardware.
5. Share your address. People read it, react to it, and write on it; only you write it.

`make` on its own lists everything.

<img src="docs/assets/screens/create-a-page.png" alt="Creating a page: the username is the address" width="620">

## What's on a page

| | |
|---|---|
| **Your markup** | Real HTML and a `<style>` block. The deprecated tags of the era — `<marquee>`, `<font>`, `<center>`, `<table>` — all work. |
| **Your rice** | A screenshot of your setup, plus the facts beside it: hardware, window manager, bar, terminal, font, theme. |
| **Layouts** | Published stylesheets you can wear, or take off somebody else's page. The eight Omarchy themes ship as layouts — Tokyo Night, Catppuccin, Lumon, Ethereal, Everforest, Gruvbox, Miasma, Hackerman — built from each theme's own colours. |
| **Reactions** | Anybody signed in can like or dislike anything you posted: the page, the rice, a shot, a build, a demo, a link, a blurb. One opinion each, and pressing it twice takes it back. |
| **Walls** | Everything you posted can be written on, and the replies stay next to the thing they answer rather than piling up at the top of the page. |
| **The rest** | Picture, greeting and mood, blurbs, a profile song, a friends list, videos and streams, demoscene demos, hardware builds. |

<img src="docs/assets/screens/profile.png" alt="A finished page: contact table, the rice, reactions under each thing, and the page's own wall" width="760">

<img src="docs/assets/screens/layouts.png" alt="The layouts you can wear, each drawn from its own theme's colours" width="760">

A page is not one blank slot. Its parts carry the ids and classes the stylesheets of the era
reach for — `.contactTable`, `.nametext`, `.orangetext15`, `.friendSpace`, `.comments` — so a
layout pasted from 2006 lands on something instead of missing everything. The full anatomy,
and the list of what a page may contain, is in the
[agent contract](docs/agent-contract.md#what-the-page-is-made-of-and-what-to-target).

## Writing your page with an agent

The interface is not only a browser. Issue a token in the studio, hand it to a coding agent,
and it reads and rewrites the same page you edit by hand — under the same rules, with a
revision check so neither of you silently overwrites the other. An agent can write your
markup, set your lists, upload your rice's pictures, and react to other people's pages
including the individual things on them.

The contract is [`docs/agent-contract.md`](docs/agent-contract.md), also served as plain
markdown at [`/agents.md`](http://localhost:3000/agents.md) — point an agent at the running
site's URL, not at the repository, and it has everything it needs.

<img src="docs/assets/screens/agents.png" alt="The agent page: what a token can do" width="760">

## The command-line client

There is a client in [`cli/`](cli/) — `ricespace login`, `ricespace page show`,
`ricespace page rice`, `ricespace rate set`, `ricespace folder clone`, and so on. It speaks the
same HTTP API an agent does, with the same token.

It is Ruby, and it is the same interpreter the site runs on: no second language, no toolchain,
no build step, and no dependency outside the standard library. One language in the repository
means the client is linted by the same RuboCop and exercised by the same `make check` as the
site.

From a checkout:

    make install            # build and install the gem, then write shell completions
    cli/exe/ricespace       # or just run it from here, with nothing installed

A gem is the whole distribution story: RubyGems puts the executable on your `PATH` and keeps
it updatable. `make install` also writes the bash, zsh and fish completion files, generated
from the client so they cannot drift from its flags.

## Working in a folder

You can keep your whole page as **files on your own machine** — edit them in your editor, see
the page drawn locally, and push when you are happy. This is the same page the studio edits,
with the same revision check in front of it.

    ricespace folder clone myspace    # write your space out as files
    cd myspace
    $EDITOR page.html                 # the markup, and a <style> block
    ricespace folder preview          # open the address it prints
    ricespace folder push             # shows the diff, then sends it
    ricespace folder watch            # or: push on every save

A folder holds your page in the API's own shapes, one file each, so nothing has to be kept in
step:

| | |
|---|---|
| `page.html` | your markup, exactly as stored |
| `rice.json` | the rice's facts — hardware, window manager, bar, terminal, font, theme |
| `blurbs.json`, `demos.json`, `builds.json`, `links.json`, `friends.json` | one file per list |
| `assets/` | the pictures themselves |
| `ricespace.toml` | which space the folder belongs to |

**The token is not in the folder.** A folder is a thing you put in git; the token stays in
`~/.config/ricespace/config.toml`.

`preview` does not draw the page itself — it hands the folder to the running site, which
renders it with [`ProfileMarkup`](app/models/profile_markup.rb) and
[`PageCss`](app/models/page_css.rb), the code that owns those rules. A `<script>` is gone in
the preview because it will be gone on the site, and a `<marquee>` runs in the preview because
it will run on the site. A preview that guessed would be worse than none.

## Who runs the place

<img src="docs/assets/ron-avatar.png" alt="Ron's avatar — the site's default profile picture" width="120">

**Ron** is the site's own account — its founder, and everybody's first friend. Make a page and
he is already on your friends list, the way the era's sites opened.

<img src="docs/assets/ron.png" alt="Ron in his man cave — tinkering on a rice, arcade cabinets behind him" width="640">

## Who can do what

Reading is open. Writing needs an account: your page, your rice, your reactions, your
comments, your friends list. Reactions and comments are signed in only, so every number and
every remark has somebody behind it — there is no anonymous path and nothing to type a name
into.

<img src="docs/assets/screens/wall.png" alt="Somebody else's page, signed out: the reactions you would leave and the walls you would write on" width="760">

## Licence

**AGPL-3.0-or-later.** See [`LICENSE`](LICENSE).

The point of that choice: if you run this as a service, section 13 applies to you — the people
using your instance are entitled to the source of the version you are running, including your
changes. Take it, run it, modify it, charge for it; what you cannot do is take it, change it,
and keep the changes to yourself while other people use them. That is the clause that stops a
closed product being built on this work.

It is a free-software licence, not an anti-commercial one. It does not forbid anybody from
selling a RiceSpace service. Nobody can be prevented from doing that by an open-source licence,
and a licence that did forbid it would not be open source.

## Running it

Ruby 3.4.3 and SQLite. No Node.

    bin/setup      # bundle install, prepare the database
    bin/dev        # serve on http://localhost:3000

    bin/rails test   # Minitest
    bin/rubocop      # style
    bin/ci           # everything CI runs, in the same order

An empty site is a poor way to see what the site is, so there is a demo set to fill it with —
the three real pages, one page wearing each layout, two that write their own CSS instead, a
rice drawn for every account, and enough friends, comments and reactions for the directory and
the ranking to have something in them:

    bin/rails demo:populate   # refresh the curated demo content

It is deliberately not part of `db:seeds`. Population refreshes the named demo pages, adds
missing content, and leaves account IDs, credentials and uploaded pictures alone. Repeating it
does not duplicate lists or reactions. A failed run rolls back its database changes. The
content lives in `lib/demo_site/spaces.rb`; the rices are drawn by `lib/demo_site/rice_art.rb`
from each account's own facts, so a picture cannot contradict the page it sits on.

The README's own pictures are drawn the same way — from the running site, not by hand:

    bin/shots        # against http://127.0.0.1:3010

## How a page is kept safe

A page is stored exactly as its author wrote it and cleaned **on the way out**: markup against
an allowlist ([`app/models/profile_markup.rb`](app/models/profile_markup.rb)), stylesheets
rebuilt as a real sheet with fetch-and-execute rules removed
([`app/models/page_css.rb`](app/models/page_css.rb)). The one thing a RiceSpace page cannot
contain is JavaScript — not in the markup, not as a `javascript:` URL, not through a CSS fetch.
Everything else about the layout is the author's.

### Hosting

The space **runs locally**. When it is put back on a host it runs as two systemd units — the
Rails server bound to loopback, and a tunnel in front of it — and deployment is
`make deploy` (rsync, migrate, seed, restart) against `DEPLOY_HOST`/`DEPLOY_PATH`.

A redeploy must not carry `storage/`, which holds the database and the attached pictures, or
`.bundle`, bundler's config — that lives outside the app precisely so a redeploy cannot delete
it. Whatever else changes, those two paths stay.

[`ROADMAP.md`](ROADMAP.md) says what is next, and what is deliberately not being built.
