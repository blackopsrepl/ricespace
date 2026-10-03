# Writing a RiceSpace page

RiceSpace hosts profile pages: one page per account, written in HTML and CSS by
whoever owns the account. Most owners write theirs in the studio in a browser.

This document is for the other case: the owner has handed you an agent token, and
you are a second editing tool for the page they already have. Nothing about the
page is yours to own — you read it, change it, and write it back, and the owner may
be editing the same page at the same time.

Every path below is relative to the space's own address. Ask the owner for it, or
read it from the config the CLI writes; the API is at `/api/v1` on that host, and
this document never names one.

## Get a token

The owner issues an agent token in the studio and hands it to you. It looks like
`rs_` followed by 48 hex characters, and it is shown exactly once; if it is lost,
the owner issues another and revokes the old one.

Send it as a bearer token on every request:

    Authorization: Bearer <token>

The token identifies one account. There is no other session: no cookies, no CSRF
token, no login step.

## The page's markup

    GET /api/v1/profile

Response:

    {
      "profile": {
        "username": "vittorio",
        "url": "<the site>/profiles/vittorio",
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

## Everything else on the page

The rice, the links, the demos, the hardware, the friends and the blurbs are their
own endpoints, so a client can manage the whole page and not only its markup:

    GET /api/v1/showcase      the rice: its facts and its shots
    PATCH /api/v1/showcase    change only the fields you send

    GET /api/v1/page          every list on the page
    PUT /api/v1/page          replace the lists you send, leave the rest alone

`GET /api/v1/showcase` returns the rice whether or not it has been built: an account
that never made one gets an empty showcase, not a 404. The response carries the facts
under their own keys (`facts.window_manager`) and as a list of filled-in pairs
(`filled`), because the keys are what a script sets and the list is what a terminal or
a page renders. Shots are listed with their captions and byte sizes.

`PATCH /api/v1/showcase` takes only the fields to change and leaves the rest alone. A
`PATCH` with no existing showcase creates one. The details field takes the same markup
as the page, cleaned on render by the same allowlist:

    {"showcase": {"title": "Purple on a ThinkPad", "window_manager": "Hyprland"}}

`PUT /api/v1/page` is whole-list replacement, atomic per kind: every entry of a list
is validated before any of it is written, so a refused entry cannot leave a page half
rewritten. A key you do not send is untouched; a key sent as an empty list is cleared.
That is what makes it idempotent from a shell script.

    {"page": {
      "links":   [{"url": "https://www.youtube.com/watch?v=…", "title": "what to call it"}],
      "demos":   [{"title": "…", "group": "…", "party": "…", "year": 1994,
                   "platform": "…", "category": "…", "placing": 1, "url": "…", "note": "…"}],
      "builds":  [{"title": "…", "kind": "rack", "summary": "…", "specs": "…",
                   "cooling": "…", "details": "markup"}],
      "friends": [{"username": "cordelia"}],
      "blurbs":  [{"title": "Interests", "body": "markup"}]
    }}

Friends are usernames and must exist already; the other four carry their own facts.
A refused list is reported whole in `error.details` and the list you already had is
left intact.

The command-line client speaks this API with the same token — see `cli/` in the
repository (`ricespace page show`, `ricespace page rice --theme …`, `ricespace page
links`, and so on).

## The pictures

The lists name pictures; this endpoint carries the bytes. An agent editing a folder
needs it, because a page that names a screenshot it cannot upload is a page that
cannot be moved.

    POST /api/v1/images            multipart: kind, file, and caption or record
    DELETE /api/v1/images/:id?kind=shot
    PATCH /api/v1/images/order     {"kind": "shot", "ids": [3, 1, 2]}

`kind` is `shot` (a rice screenshot), `build` (a hardware photo) or `picture` (the
account's own profile picture). `record`, for a build photo, names the build by its
**title** — an id is the site's business, a title is the author's; an id is accepted
too if you already have one. `caption` becomes the line under the picture.

Order is set **whole**, in one request, as the list of ids in the order you want. Ids
that are not this account's are ignored and anything you leave out keeps its place
afterwards, so a drifted order converges rather than failing. There is no
one-picture-at-a-time move to call.

Two ceilings, both reported with `error.code`: `file_too_large` when one file exceeds
its own limit (5 MB for the profile picture, 8 MB for a shot or a build photo), and
`over_quota` when the account's total stored pictures would pass 200 MB. A refused
upload writes nothing.

## What other people think of a page

The one fact on a page its owner does not write. Two directions, and they are different
operations:

    GET /api/v1/ratings              the reactions on the page YOUR token speaks for
    PUT /api/v1/ratings/:username    your opinion of that page
    PUT /api/v1/ratings/:username/:kind/:id
                                     your opinion of one thing they posted

The read answers "what do people think of my page" — the number the owner's own dashboard
shows. It is not how you read somebody else's score; that is on their page, which is the
page a visitor sees.

    {"rating": {"username": "vittorio", "score": 3, "likes": 4, "dislikes": 1,
                "raters": 5, "yours": null}}

The write takes one of three words:

    {"rating": "like"}      {"rating": "dislike"}      {"rating": "none"}

`none` withdraws your opinion; without it there is no way to un-react. The response
carries the new score, what you said (`yours`), and whether anything actually
changed (`changed`) — the last matters because this is a `PUT` and not the browser's
toggle: sending the same opinion twice leaves it as it was and answers `"changed": false`
rather than flipping it. A retried request must not reverse somebody's opinion.

### Reacting to what was posted, not only to the page

On a page, the thing a person reacts to is the thing that was posted — the rice, a shot of
it, a build, a demo, a link. `PUT /api/v1/ratings/:username/:kind/:id` is the same act aimed
at one of those instead of at the page:

    PUT /api/v1/ratings/vittorio/showcase/12   {"rating": "like"}

The kinds are `page`, `showcase`, `shot`, `build`, `photo`, `demo`, `link`, `blurb`. The id
is the object's own id, which `GET /api/v1/page` gives you for everything on the page. A post
that is not on `:username`'s page is `404 unknown_post`; a kind that does not exist is
`422 unknown_kind`.

A page's score is **the page plus everything posted on it**, because that is how the page
itself counts: a like on the rice lifts the page that carries it. A client reading
`GET /api/v1/ratings` therefore sees one number assembled from everything, not only from the
reactions left on the page itself.

One opinion per account per thing. You cannot react to your own post, page or otherwise:
`422 own_post`. An unknown page is `404 unknown_page`. An unknown opinion is
`422 unknown_rating`.

The score is `likes - dislikes`; the site itself shows only the score and never breaks it
down, but a client may. The front page's ranking is **not** this number — it orders by how
many people reacted at all, which is why a page with many mixed opinions can outrank a
page with a handful of likes.

## Walls

Anything that can be reacted to can be written on, and the wall is the same in both cases:

    POST   /api/v1/...               not exposed over the API — walls are written in the browser

Comments are **signed in only and always attributable** — there is no anonymous path, and no
name to send. The kinds and ids are the same ones the reactions use.

## What an agent editing a folder should expect

`ricespace folder clone` writes the page as files in the API's own shapes —
`page.html`, `rice.json`, one JSON file per list, and `assets/` holding the pictures.
`ricespace folder push` sends them back. Two properties of the API make that safe and
are worth knowing if you build your own client:

- A list you send is compared on the fields a folder carries. Extra keys the API
  returns — a build's `photos`, a demo's `embeds`, the `platform` derived from a
  link's url — are the site's own and can be ignored on a round trip.
- The rice's facts arrive at the top level (`title`, `summary`, `details`) and under
  `facts`; both are the same values.

## What the page is made of, and what to target

A page is not one blank slot. It has an anatomy, and its parts carry the ids and
classes the stylesheets of the era reach for — so a layout pasted from 2006 lands on
something instead of missing everything:

    .contactTable   the name, greeting, mood and picture block
    .profile-pic    the picture beside the name
    .contactInfo    the text beside the picture
    .nametext       a display name (the page's, a friend's, a commenter's)
    .orangetext15   a section heading
    #profile        the markup the owner wrote, and only that
    #showcase       the rice — .rice-frame, .rice-shot, .rice-title, .fact
    #watch          videos and streams, embedded from where they are hosted
    #demos          the demoscene — .demo, .demo-title, .demo-credit, .demo-placing
    #hardware       physical builds — .build, .build-title, .build-details
    .blurb          one titled block of the owner's text, with .blurb-title
    .friendSpace    the friends list — .top8, .friend, .friendCount
    .comments       comments and their form — .comment, .comment-body, .commentCount
    .audio.player   the profile song, with audio.song
    #profile-stamp  when the page was last changed

Write to those names and your page's look survives. Renaming one would break every
layout anybody has written, so they are treated as a contract.

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

| Status | Code | When |
|---|---|---|
| 401 | `invalid_token` | missing, malformed or unknown token |
| 400 | `missing_parameter` | the request carried no `profile.document` or no `profile.version` |
| 409 | `stale_document` | the page moved since you read it; `details.current_version` is the revision to re-read from |
| 422 | `invalid_profile` | the document was refused; `details` lists why |
| 422 | `invalid_showcase` | the rice was refused; `details` lists why |
| 422 | `invalid_page` | one or more list entries were refused; `details` lists which |
| 404 | `unknown_page` | a reaction named a page that does not exist |
| 404 | `unknown_post` | a reaction named a post that is not on that page |
| 422 | `own_post` | an account tried to react to its own post, page or otherwise |
| 422 | `unknown_kind` | a reaction named a kind that is not reactable |
| 422 | `unknown_rating` | a reaction that is not `like`, `dislike` or `none` |
| 422 | `invalid_image` | the file was not an image; `details` lists why |
| 422 | `file_too_large` | one file passed its own size limit |
| 422 | `over_quota` | the account's stored pictures would pass 200 MB |
| 400 | `missing_file` | an upload arrived with no file |
| 404 | `unknown_record` | a build photo named a build that is not there |

## A worked example

    TOKEN=...
    BASE=<the space's address>
    # Read: note the version, and see which of the owner's CSS rules survived.
    curl -s -H "Authorization: Bearer $TOKEN" "$BASE/api/v1/profile"
    # Write: send the whole page back with the version you just read.
    curl -s -X PATCH -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d '{"profile":{"document":"<style>body { background: #111; color: #0ff }</style><marquee>welcome</marquee>","version":1}}' \
      "$BASE/api/v1/profile"
