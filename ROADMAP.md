# Roadmap

What is being built, in the order it is being built, and what is deliberately not
being built. Each item states the problem it closes; an item without a problem is
not a roadmap entry, it is a wish.

## Now

### 1. Make the write endpoints cost something

**Problem.** Sign-up, sign-in and the comment form are open to the internet, and
nothing bounds how often they are called. A page whose whole point is that anyone
can join is also a page where anyone can spin a loop against `POST /session` or
`POST /registration`. There is no lockout and no delay, so the only thing standing
between a credential list and an account is the password itself.

**Done when** each of those endpoints refuses a burst from one client, the refusal
is a plain `429`, and the limit is visible in the code rather than in a proxy
config nobody reads.

**Done.** `SessionsController` (10 per 3 minutes) and `RegistrationsController` (5 per
3 minutes) declare their limits as constants beside the code that enforces them, refuse
with a `429`, and the refusal is a page rather than a bare body. Per client, not per
account — locking an account after failed attempts would let anyone lock anybody out.
Both are tested in `account_lifecycle_test.rb`.

### 2. Let a person close their account

**Problem.** An account can be created and can never be removed by its owner. For a
product whose pitch is "put yourself on a page", that is the wrong default: the
person who wants out has to ask somebody. Every model already cascades from `User`,
so the capability exists and only the door is missing.

**Done when** a signed-in owner can delete their account from the studio, the
confirmation is deliberate rather than a stray click, and the page, picture, rice,
comments, friends and tokens all go with it.

**Done.** The studio carries the button in its own red panel, saying what goes and that
it does not undo, behind a confirmation naming the account. The site's own account is
excluded, and the test for that is what caught the seeded-Ron password problem.

### 3. Bound what one account can store

**Problem.** Uploads are bounded per picture but not per account. One account can
add rice shots and build photos without limit, so the disk is the only ceiling and
the ceiling belongs to whoever uploads most.

**Done when** each account has a stated cap on stored bytes, uploading past it is
refused with a message that says so, and the cap is one number in one place.

**Done.** The cap is `User::STORAGE_LIMIT`, and `CountedTowardStorage` (included by
`ProfilePicture`, `ShowcaseShot` and `BuildPhoto`) is what applies it, so it holds on
the studio's forms and on the API's `POST /api/v1/images` alike — an earlier version
had the number in the API controller, which left the browser path unbounded.

## Next

### 4. A folder that is your page

**Problem.** The studio is the only way to edit a page, and a page is a document
somebody writes. There is no way to keep your page as files, edit it in your own
editor, or see it drawn before it is published.

**Done when** `ricespace folder clone/push/preview/watch` work end to end: the folder
holds the page in the API's own shapes, `preview` draws it with the site's own cleaner
rather than a second implementation of it, and `push` sends what changed and nothing
else. **Done** — see "Working in a folder" in the README. `preview` and `watch` need
the site running, which is the price of a preview that cannot lie about the rules.

### 5. Put it back on a host

The space ran on the DMZ VM behind a cloudflared quick tunnel, whose hostname
changes on every restart — fine for showing it to somebody, wrong for a URL anyone
writes down. It is local again while that is decided. The DMZ host already runs a
named cloudflared tunnel, so a fixed address is a dashboard entry and a choice of
domain, not code.

### 6. An installable CLI

`cli/` is a working Rust client — `ricespace login`, `page show`, `page links`,
`page rice`, `rate show|set`, `folder clone|push|preview|watch`.

**Done.** `cargo install --git https://github.com/blackopsrepl/ricespace ricespace`, or
`make install` from a checkout. It is a Rust binary with no runtime dependencies, so the
distribution is `cargo install` and nothing else: no installer script, no release archive,
no checksum to verify. `make install` also writes the bash, zsh and fish completions,
generated from the binary.

## Later

- **A second pair of eyes on a page.** The sanitising rules are specified by
  `profile_markup_test.rb` and `page_css_test.rb` and are the security boundary of
  the whole product. They deserve a review pass that is not the author's.
- **Export a page.** If the page is really yours, you should be able to take it out
  — the document, the stylesheet and the pictures, as files.

## Licence

**AGPL-3.0-or-later.** A service built on this has to publish the source of the version
it runs, including its changes — that is section 13, and it is the whole reason for
choosing this licence over MIT or Apache. Fork it, run it, charge for it; what you
cannot do is keep your changes closed while other people use them.

It does not forbid anybody from running a commercial service, and no open-source
licence could: "no productization" and "open source" are not both available. What is
enforced here is the published-source obligation, which is the enforceable version of
not wanting this taken private.

## Not doing

- **Sign in with X.** X sign-in needs an app registration from X; there is none, so
  the feature has no way to exist. It is not waiting on code.
- **JavaScript on a page.** A RiceSpace page cannot contain it. That is the
  deliberate boundary the sanitising rules exist to hold, not a gap.
- **Moderation tooling.** Comments are signed in because an unaccountable author is
  the actual problem; a second system for hiding what an accountable author wrote
  is a different product.
- **A feed.** There is no stream and nothing arrives on the front page on its own.
  You find a page because somebody showed it to you, or because other people rated
  it — not because an algorithm decided you should see it. The front page is still a
  directory; it now has a ranking in it, which is the old kind and not a feed.
- **Two rankings.** There is one number per page and one list. Likes move it up and
  dislikes move it down, and the page says neither — the score is the whole of what a
  visitor is told, because a site that explains how to game its ranking is a site
  whose ranking is gamed.
