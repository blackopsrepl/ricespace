# RiceSpace

**A page per account, and the HTML and CSS to fill it.**

<img src="docs/assets/screens/home.png" alt="The RiceSpace front page: a directory of rices and pages" width="720">

You get a page, a screenshot of your setup — your *rice* — and the whole page is
yours to style. Not a form with a theme picker: real markup and a real stylesheet.
Paste a layout from 2006, write your own CSS, put a `<marquee>` on it. If you lived
through the era when your profile page was the most interesting thing you owned,
this is that, with a proper editor and an API.

## Try it

1. **[Create a page](https://bathroom-police-vote-festivals.trycloudflare.com/registration/new)** — pick a username, that becomes your address.
2. You land in the **studio**. Write your markup and stylesheet; save is instant.
3. Add your **rice** — a screenshot of your desktop and what is in it (hardware,
   window manager, bar, terminal, font, theme).
4. Fill in the rest: a picture, blurbs, a song, friends, videos, demos, hardware.
5. Share your address. People read it; only you write it.

*That link is a temporary address for the running instance — see
[Running it](#running-it).*

<img src="docs/assets/screens/profile.png" alt="A finished page: avatar, a rice, and the facts about it" width="720">

## What's on a page

| | |
|---|---|
| **Your markup** | Real HTML and a `<style>` block. Deprecated tags from the era — `<marquee>`, `<font>`, `<center>`, `<table>` — all work. |
| **Your rice** | A screenshot of your setup, plus the facts: hardware, window manager, bar, terminal, font, theme. |
| **Layouts** | Published stylesheets you can wear, or take off someone else's page. |
| **The rest** | Picture, greeting and mood, blurbs, a profile song, a friends list, videos and streams, demoscene demos, hardware builds. |

<img src="docs/assets/screens/layouts.png" alt="The layouts you can wear" width="720">

## Writing your page with an agent

You can also hand a coding agent a token and let it write the page for you. Issue a
token in the studio, give it to the agent, and it reads and rewrites the same page
you edit in the browser — under the same rules, with a revision check so neither of
you silently overwrites the other. The contract is
[`docs/agent-contract.md`](docs/agent-contract.md), also served as plain markdown at
`/agents.md`.

There is a command-line client in [`cli/`](cli/) — `ricespace login`, `ricespace
page show`, `ricespace page rice`, and so on.

## Who runs the place

<img src="docs/assets/ron-avatar.png" alt="Ron's avatar — the site's default profile picture" width="120">

**Ron** is the site's own account — its founder, and everybody's first friend. Make
a page and he is already on your friends list, the way the era's sites opened.

<img src="docs/assets/ron.png" alt="Ron in his man cave — tinkering on a rice, arcade cabinets behind him" width="640">

## Who can do what

Reading is open. Writing needs an account: your page, your rice, your comments,
your friends list. Comments are signed in only, so every comment has somebody behind
it.

## Running it

Ruby 3.4.3 and SQLite. No Node.

    bin/setup      # bundle install, prepare the database
    bin/dev        # serve on http://localhost:3000

The live instance runs as two systemd units — the Rails server on loopback and a
cloudflared quick tunnel in front of it — so the public address changes when the
tunnel restarts and is read with `ricespace-url`. The deploy loop, and the two paths
a redeploy must not delete, are in [`ROADMAP.md`](ROADMAP.md)'s neighbourhood: see
the Hosting section below.

    bin/rails test   # Minitest
    bin/rubocop      # style
    bin/ci           # everything CI runs, in the same order

### Hosting

    ricespace.service         the Rails server (RAILS_ENV=production)
    ricespace-tunnel.service  a cloudflared quick tunnel to that server
    ricespace-url             prints the current public address

Deployment is rsync, migrate, seed, restart — and it must not carry `storage/` (the
database and the attached pictures) or `.bundle` (bundler's config, kept outside the
app precisely so a redeploy cannot delete it):

    rsync -az --delete --exclude '.git' --exclude 'cli/target' \
      --exclude 'tmp/' --exclude 'log/' --exclude 'vendor/' \
      --exclude 'storage/' --exclude '.bundle' \
      -e ssh ./ <user>@<host>:<app-path>/
    ssh <user>@<host> 'cd <app-path> && RAILS_ENV=production bundle exec rails \
      db:migrate db:seed && sudo systemctl restart ricespace'

### How a page is kept safe

A page is stored exactly as its author wrote it and cleaned **on the way out**:
markup against an allowlist ([`app/models/profile_markup.rb`](app/models/profile_markup.rb)),
stylesheets rebuilt as a real sheet with fetch-and-execute rules removed
([`app/models/page_css.rb`](app/models/page_css.rb)). The one thing a RiceSpace page
cannot contain is JavaScript — not in the markup, not as a `javascript:` URL, not
through a CSS fetch. Everything else about the layout is the author's.

[`ROADMAP.md`](ROADMAP.md) says what is next, and what is deliberately not being
built.
