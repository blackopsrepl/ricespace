# RiceSpace

<img src="docs/assets/ricespace-mascot.png" alt="RiceSpace mascot — a rice-grain CRT with a monitor-cable antenna" width="200">

**A page per account, and the HTML and CSS to fill it — on this server, or on no server at all.**

<img src="docs/assets/screens/home.png" alt="The RiceSpace front page: the most-reacted-to pages, then the directory" width="760">

You get a page, a screenshot of your setup — your *rice* — and the whole page is yours to
style. Not a form with a theme picker: real markup and a real stylesheet. Paste a layout from
2006, write your own CSS, put a `<marquee>` on it. If you lived through the era when your
profile page was the most interesting thing you owned, this is that, with a proper editor,
an API — and, when you want it, no server in the middle.

RiceSpace is two things that share one page format. **A site** you can run, with accounts,
a directory and a ranking. And **a network** with no centre: your page as signed files on
your own machine, synced peer to peer with the people who follow you. The site is one node
on that network — the loudest one, not the only one.

## Try it

    make setup     # install gems, prepare the database
    make serve     # http://localhost:3000

Then:

1. **Create a page** — pick a username, that becomes your address on this node.
2. You land in the **studio**. Write your markup and stylesheet; save is instant.
3. Add your **rice** — a screenshot of your desktop, and what is in it.
4. Fill in the rest: a picture, blurbs, a song, friends, videos, demos, hardware.
5. Share your address. People read it, react to it, and write on it; only you write it.

`make` on its own lists everything.

<img src="docs/assets/screens/create-a-page.png" alt="Creating a page: the username is the address" width="620">

Or skip the server entirely — [take your page peer to peer](#your-page-without-a-server).
No signup, no host, no one to ask. Your account is a keypair you generate on your own
machine, and your page is files you sign.

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
`~/.config/ricespace/config.json`.

`preview` does not draw the page itself — it hands the folder to the running site, which
renders it with [`ProfileMarkup`](app/models/profile_markup.rb) and
[`PageCss`](app/models/page_css.rb), the code that owns those rules. A `<script>` is gone in
the preview because it will be gone on the site, and a `<marquee>` runs in the preview because
it will run on the site. A preview that guessed would be worse than none.

## Your page, without a server

The same page, with nobody running it. Your account is a keypair on your own machine; your
page is files you sign; your readers are the people who follow you, syncing directly with
you or with anyone who holds a copy. No signup, no host, no chain, no tokens, no relays —
TLS between workstations that opted in, each pinned to keys they already know.

    ricespace identity create              # your account: a keypair, nothing to sign up for
    ricespace folder sign --all            # seal the folder into your signed feed
    ricespace peer serve                   # answer sync requests (port 7676, TLS)
    ricespace peer add <key> ron --at host:port   # follow somebody
    ricespace peer sync                    # pull your follows up to date, pinned to their keys

Your address is your public key, shown as `rice:` plus 12 characters. Names are petnames —
`ron` is who *you* call ron, an entry in your own friends list mapping a name to a key, and
the page always shows the key beside the name so a clash is visible, never silent.

Follow the flow: create the identity, write the page as files, sign the folder (a
`manifest.json` rides along as the folder's proof), serve it, and hand your key to a friend.
They `peer add` your key, `peer sync`, and your page renders on their machine — cleaned by
the same rules, read-only, with your rice, your lists and your wall. When you go offline,
anyone who follows you still serves your page to anyone who follows them. That is the whole
delivery story: friends carry copies.

The two halves meet wherever you want them to. A node operator runs the site as usual and it
is one peer among others: replicated pages render at `/peers` beside local ones, ranked the
same way, reacted to and written on with the node signing as you. Linking is one paste in
the studio — your master key from `identity show` — plus authorising the node's device key
from the machine holding your master. The README's [operator section](#running-a-node)
walks through it; [`docs/p2p-spec.md`](docs/p2p-spec.md) states the protocol underneath.

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

On the network the same rule holds without a server to enforce it: everything is signed,
so a reaction or a comment that does not verify is not stored, and a page whose history was
rewritten shows as compromised rather than rendering the forgery. The signature is the
account.

<img src="docs/assets/screens/wall.png" alt="Somebody else's page, signed out: the reactions you would leave and the walls you would write on" width="760">

## Keeping the keys

In the P2P shape the key *is* the account — whoever holds it is you, and there is no
password reset. Three habits, in order of importance:

1. **Back the master up on paper, now.** `ricespace identity backup` prints it once. Two
   places, offline. The master never signs day to day, so paper is where it lives.
2. **Work from devices, not the master.** Each workstation holds its own device key; the
   master only ever signs `device-add`, `rotation` and `revocation`. A stolen laptop costs
   one device: `identity device-revoke` cuts it off, and everything it signed while it was
   yours keeps verifying.
3. **Know your friends before you need them.** Losing every key loses the name — unless
   your friends hand it back. Each friend runs `identity endorse` on their own machine
   (master-signed — a device signature would never verify) and you carry the pairs into
   `identity recover`: a majority of the friends on your list, and only friends who have
   been there a while count. Keep people you actually know on it.
4. **A second workstation joins, it never copies.** `identity join` mints the new
   machine its own device key; you authorise it from the master machine with
   `identity device-add`. The master secret never travels.
5. **Leaving is a record too.** `folder goodbye` tombstones the feed — honest peers
   drop the page, nothing new verifies after it. Closing the site account does the
   same when it is linked. Replicas keep the proof; `folder prune` drops other
   people's copies off your own disk.

A stolen key cannot rewrite your past: old versions are signed and already replicated by
your friends, so any friend holding one can prove a rewritten one is a fork. The thief can
only append junk until your revocation spreads — which is why revoking fast matters more
than anything else on this list.

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

### Running a node

The same site, as one peer among others. Replicated feeds render at `/peers` beside local
pages — same cleaners, same ranking rule, read-only — and a linked account reacts and
comments on them with the node signing as its device. Three steps:

1. **Give the node its device key.** `ricespace peer keygen` prints a fresh pair, once.
   Put the secret in a file only the service user can read (mode 0600) and point the
   service at it with `RICESPACE_NODE_SECRET_FILE`. The public half is shown on the
   node's `/peers` page for feed owners to authorise.
2. **Link the account.** In the studio, under *Your feed on the network*, paste the master
   key from `ricespace identity show`. The studio says whether the node may sign yet.
3. **Authorise the node, from the machine holding the master.**
   `ricespace identity device-add <the node's public key>` — master-signed, synced on the
   next import. From then on this node's saves publish into your feed and its reaction
   buttons sign as you. Revoke the same way if the node ever stops being yours.

[`ROADMAP.md`](ROADMAP.md) says what is next, and what is deliberately not being built.
