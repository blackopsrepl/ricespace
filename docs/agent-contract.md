# Writing a RiceSpace page

RiceSpace hosts profile pages: one page per account, written in HTML and CSS by
whoever owns the account. Most owners write theirs in the studio in a browser.

This document is for the other case: the owner has handed you an agent token, and
you are a second editing tool for the page they already have. Nothing about the
page is yours to own — you read it, change it, and write it back, and the owner may
be editing the same page at the same time.

## Get a token

The owner issues an agent token in the studio and hands it to you. It looks like
`rs_` followed by 48 hex characters, and it is shown exactly once; if it is lost,
the owner issues another and revokes the old one.

Send it as a bearer token on every request:

    Authorization: Bearer <the token>

The token identifies one account. There is no other session: no cookies, no CSRF
token, no login step.

## Read the page

    GET /api/v1/profile

Response:

    {
      "profile": {
        "username": "vittorio",
        "url": "http://localhost:3000/profiles/vittorio",
        "document": "<style>body { background: #000 }</style><marquee>hi</marquee>",
        "html": "<marquee>hi</marquee>",
        "css": "body { background: #000; }",
        "version": 3,
        "updated_at": "2026-10-03T09:00:00Z",
        "limits": { "document_bytes": 200000, "html_bytes": 100000, "css_bytes": 50000 }
      }
    }

Three of those matter, and they are not interchangeable:

- `document` — what is stored, byte for byte, exactly as the owner wrote it. This
  is the whole page, stylesheet included, and it is what you edit.
- `html` — the page's markup as a visitor will get it, cleaned.
- `css` — the page's stylesheet, cleaned, on its own. A profile's layout lives in
  `<style>` and is not scoped to the markup, so this is where the `position`,
  `visibility` and `display` rules are. If you never read it, you are editing blind.

`version` is the revision you just read; you send it back when you write.

## Write the page

    PATCH /api/v1/profile
    Content-Type: application/json

    {
      "profile": {
        "document": "<style>body { background: #000 }</style><marquee>hi</marquee>",
        "version": 3
      }
    }

The write replaces the whole document. Send the complete page — markup and
stylesheet — not a fragment and not a patch. The response has the same shape as
the read, with a new `version`.

`version` is the revision you edited. A write without it is a blind write and is
refused with `400`. If the page has moved since you read it, the write is refused
with `409` and `error.code` of `stale_document`, and `error.details.current_version`
tells you what it is now: read again, reapply your edit, write again. Never retry a
write blindly — that is how you would silently discard the owner's edits, which
they may be making in the studio at the same time.

## What you may write

Ordinary HTML, including the deprecated presentational tags that profile pages of
the era were built from: `<marquee>`, `<font>`, `<center>`, `<blink>`, `<table>`,
`<hr>`, and inline `style` attributes.

And a `<style>` block, which is a real stylesheet: it is written into the page
after the site's own styles, so it can restyle anything, the site's chrome included.
`body { background: ... }`, `.main { position: absolute; left: 50%; margin-left:
-400px }`, `.orangetext15 { visibility: hidden }` all work. `position`, `z-index`,
`display`, `visibility`, `overflow`, `!important` and arbitrary selectors survive.
Write the sheet you want; it will not be reordered or scoped for you.

What is removed from a stylesheet, and why:

- At-rules (`@import`, `@media`, ...): `@import` makes the browser fetch a
  stylesheet from a host the owner does not control.
- Comments (`/* ... */`), which the sites of the era stripped too.
- Any declaration whose `url()` is not `http(s)`, site-relative or a fragment.

What is removed from the markup, whatever you send:

- `<script>`, `<iframe>`, `<object>`, `<embed>`, `<form>`, `<meta>`, `<link>`,
  `<base>`, `<svg>` — removed together with their contents. JavaScript is the one
  thing a RiceSpace page cannot contain.
- `on*` event-handler attributes, e.g. `onclick`, `onerror`.
- Links to anything but `http(s)` URLs, site-relative paths, anchors and
  `mailto:`. Images likewise, minus `mailto:`.
- `javascript:` and `data:` URLs.

After writing, read `html` and `css` back and check what actually arrived.

## Errors

Every failure is JSON with a stable code:

    { "error": { "code": "invalid_token", "message": "...", "details": [...] } }

- `401 invalid_token` — missing, malformed or unknown token.
- `400 missing_parameter` — the request carried no `profile.document` or no
  `profile.version`.
- `409 stale_document` — the page moved since you read it; `details.current_version`
  is the revision to re-read from.
- `422 invalid_profile` — the document was refused; `details` lists why.

## A worked example

    TOKEN=...
    # Read: note the version, and see which of the owner's CSS rules survived.
    curl -s -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/profile
    # Write: send the whole page back with the version you just read.
    curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"profile":{"document":"<style>body { background: #111; color: #0ff }</style><marquee>welcome</marquee>","version":1}}' \
      http://localhost:3000/api/v1/profile
