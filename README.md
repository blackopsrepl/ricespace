# RiceSpace

A page per account, written in HTML by whoever owns the account — usually by
their coding agent, working from a token.

The two halves are the same feature seen from two chairs:

- **The owner's chair.** Create an account, land in the studio, write the page.
  Deprecated presentational HTML is allowed — `<marquee>`, `<font>`, `<center>`,
  `<table>`, inline `style` — because that is the visual language of a profile
  page from the era this imitates.
- **The agent's chair.** Issue an agent token and hand it to a coding agent.
  `GET /api/v1/profile` returns the page and what it actually renders to; `PATCH`
  replaces it. The agent codes against [`docs/agent-contract.md`](docs/agent-contract.md),
  served raw at `/agents.md`.

## Requirements

Ruby 3.4.3 and SQLite. No Node runtime is needed to serve the application —
importmap loads JavaScript from the browser, and Tailwind is compiled by the
`tailwindcss-rails` gem's own binary.

## Setting up

    bin/setup           # bundle install, prepare the database, clear logs and tmp
    bin/dev             # serve on http://localhost:3000

`bin/dev` runs the server and the Tailwind compiler together; it uses `foreman` if
you have it, and otherwise starts both processes itself, because the Rails
template's habit of installing foreman globally fails on a machine whose system
gem directory is not writable and leaves you with no server at all. Set `PORT` if
3000 is taken — a failed bind is reported, not worked around.

## The test suite

    bin/rails test      # Minitest, including the sanitising and API contract tests
    bin/rubocop         # style
    bin/ci              # everything CI runs, in the same order

`bin/ci` is the full gate: setup, RuboCop, `bundler-audit`, `importmap audit`,
Brakeman, the test suite and a seed replant.

## How author markup is handled

A profile document is stored exactly as its author wrote it, and cleaned **on the
way out**, by [`app/models/profile_markup.rb`](app/models/profile_markup.rb).
Nothing else in the application renders an author's markup.

Two consequences worth knowing before changing anything:

- Tightening the allowlist is a code change and nothing else. There is no
  migration of stored pages, and no version of a page that was cleaned under
  older rules.
- Every render parses the document, so the sanitiser is on the hot path of every
  profile view. It is written to be cheap: the document is size-capped, scrubbed
  to valid UTF-8, and pruned with one allowlist pass, so a hostile page costs a
  bounded amount of work.

`profile_markup_test.rb` is the specification of what survives: the tags, the
attributes, the inline CSS that is parsed rather than trusted, the URL policy,
and the elements that are removed with their contents.

## Two writers, one page

The owner has the page open in the studio while their agent writes it over the
API. Each write carries the revision it was built on, and a write built on a
revision that has since moved is refused: the studio hands the owner's text back
in the editor, the API answers `409 stale_document` with the current version.
Nothing merges two pages and nothing overwrites silently — see
`Profile#version`.
