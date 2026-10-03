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

### 2. Let a person close their account

**Problem.** An account can be created and can never be removed by its owner. For a
product whose pitch is "put yourself on a page", that is the wrong default: the
person who wants out has to ask somebody. Every model already cascades from `User`,
so the capability exists and only the door is missing.

**Done when** a signed-in owner can delete their account from the studio, the
confirmation is deliberate rather than a stray click, and the page, picture, rice,
comments, friends and tokens all go with it.

### 3. Bound what one account can store

**Problem.** Uploads are bounded per picture but not per account. One account can
add rice shots and build photos without limit, so the disk is the only ceiling and
the ceiling belongs to whoever uploads most.

**Done when** each account has a stated cap on stored bytes, uploading past it is
refused with a message that says so, and the cap is one number in one place.

## Next

### 4. A named home

`ricespace-url` prints a random `*.trycloudflare.com` hostname that changes on
restart. That is fine for showing the thing to somebody and wrong for a URL anyone
writes down. The DMZ host already runs a named cloudflared tunnel; pointing a
hostname at it is a dashboard entry and a decision about which domain, not code.

### 5. An installable CLI

`cli/` is a working Rust client — `ricespace login`, `page show`, `page links`,
`page rice`. `cli/install.sh` installs it into a prefix with generated shell
completions. What is missing is distribution: a tagged release, a built binary per
platform, and a README line that says how to get it.

## Later

- **A second pair of eyes on a page.** The sanitising rules are specified by
  `profile_markup_test.rb` and `page_css_test.rb` and are the security boundary of
  the whole product. They deserve a review pass that is not the author's.
- **Export a page.** If the page is really yours, you should be able to take it out
  — the document, the stylesheet and the pictures, as files.

## Not doing

- **Sign in with X.** X sign-in needs an app registration from X; there is none, so
  the feature has no way to exist. It is not waiting on code.
- **A feed, a score, or a ranking.** The front page is a directory ordered by
  change. There is no score here and adding one changes what the product is.
- **JavaScript on a page.** A RiceSpace page cannot contain it. That is the
  deliberate boundary the sanitising rules exist to hold, not a gap.
- **Moderation tooling.** Comments are signed in because an unaccountable author is
  the actual problem; a second system for hiding what an accountable author wrote
  is a different product.
