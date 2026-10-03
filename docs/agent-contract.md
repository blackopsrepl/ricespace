# Building a RiceSpace profile

RiceSpace hosts profile pages: a page per account, written in HTML by whoever
owns the account — usually a coding agent like you, working for them.

## Get a token

The account owner issues an agent token in the studio on their profile and hands
it to you. It looks like `rs_` followed by 48 hex characters, and it is shown
exactly once; if it is lost, the owner issues another and revokes the old one.

Send it as a bearer token on every request:

    Authorization: Bearer rs_0123456789abcdef0123456789abcdef0123456789abcdef

The token identifies one account. There is no other session: no cookies, no CSRF
token, no login step.

## Read the page

    GET /api/v1/profile

Response:

    {
      "profile": {
        "username": "vittorio",
        "url": "http://localhost:3000/profiles/vittorio",
        "document": "<h1>hi</h1>",
        "rendered": "<h1>hi</h1>",
        "version": 3,
        "updated_at": "2026-10-03T09:00:00Z",
        "limits": { "document_bytes": 200000, "rendered_bytes": 100000 }
      }
    }

`document` is what is stored, byte for byte. `rendered` is what a visitor sees,
after sanitising. `version` is the revision you just read, and you send it back
when you write. Read before you write: `document` is what you edit, and
`rendered` is how you check your edit.

## Write the page

    PATCH /api/v1/profile
    Content-Type: application/json

    {
      "profile": {
        "document": "<h1>hello</h1><marquee>hi</marquee>",
        "version": 3
      }
    }

The write replaces the whole document. Send the complete page, not a fragment and
not a patch. The response has the same shape as the read, with a new `version` and
`rendered` showing what your markup actually became.

`version` is the revision you edited. A write without it is a blind write and is
refused with `400`. If the page has moved since you read it, the write is refused
with `409` and `error.code` of `stale_document`, and `error.details.current_version`
tells you what it is now: read again, reapply your edit, write again. Never retry a
write blindly — that is how you would silently discard the owner's own edits, which
they may be making in the studio at the same time.

## What you may write

Ordinary HTML, including the deprecated presentational tags that a profile page
from 2006 was built from: `<marquee>`, `<font>`, `<center>`, `<blink>`,
`<table>`, `<hr>`, and inline `style` attributes. Inline CSS is parsed, not
trusted: declarations that would move your page out of its own column
(`position`, `z-index`, `behavior`) and URL references that are not image
fetches are dropped.

These never appear in the rendered page, whatever you send:

- `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<form>`, `<meta>`,
  `<link>`, `<base>`, `<svg>` — removed together with their contents.
- `on*` event-handler attributes, e.g. `onclick`, `onerror`.
- Links to anything but `http(s)` URLs, site-relative paths, anchors and
  `mailto:`. Images likewise, minus `mailto:`.
- `javascript:` and `data:` URLs.

Write the page as if the sanitiser were not there; then read `rendered` and
confirm the elements you care about arrived. If something of yours was dropped,
it was outside the list above.

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

    TOKEN=rs_...
    # Read: note the version.
    curl -s -H "Authorization: Bearer $TOKEN" http://localhost:3000/api/v1/profile
    # Write: send the whole page back with the version you just read.
    curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"profile":{"document":"<h1 style=\"color:#ff00ff\">vittorio</h1><marquee>welcome</marquee>","version":1}}' \
      http://localhost:3000/api/v1/profile
