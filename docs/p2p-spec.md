# The P2P spec

RiceSpace without the server: one signed append-only log per account,
follow-gated replication over direct TCP. No chain, no consensus, no tokens,
no relays, no DHT.

This document is the reference. The [README](../README.md#your-page-without-a-server)
is the user-facing walkthrough; what follows is exact enough to reimplement from.

## Why this shape

Each page has one writer. Ordering is the writer's sequence number plus the
previous record's hash — a per-user hash chain. Global consensus would add
nothing: there is no multi-writer state to agree on. What two peers believe
about "what is popular" may differ; that is fine, and a chain would exist to
force agreement nobody needs.

Two consequences fall out of the shape rather than being decided:

- **History is tamper-evident, not tamper-proof.** You hold the key, so you
  *can* rewrite your past — but any friend holding an old version can prove
  the rewrite is a fork. Edits are new records, never in-place.
- **Deletion is a request.** A tombstone asks honest peers to drop the feed;
  dishonest ones keep replaying old signed copies. "Close your account" works
  against anyone you would trust to host your page, and against no one else.

## Identity

An account is an Ed25519 keypair (stdlib `OpenSSL`). The public key is the
address: 64 hex characters, shown as `rice:` plus the first 12, with the full
key one step away (`identity show`, the `/peers` page, the `[a3f9..c1]`
pair beside every petname). Two accounts differ if and only if their keys
differ. There is no registry and no signup: `ricespace identity create`
writes `~/.config/ricespace/identity.json` (0600, passphrase-encrypted PEM)
and that is the whole ceremony.

Names are petnames — entries in *your* friends list mapping a name to a key.
`ron` is who you call ron, not a global username. The UI always shows the key
beside the name; one name on two keys is a conflict badge, never a merge.
Giving up global usernames is the price of having no registry. It is paid
once, here.

### Devices

One identity, many devices. The master key stays offline — paper, via
`identity backup`, which prints it exactly once. Each workstation holds its
own device key plus the master's public half, authorised by a `device-add`
record the master signed. Day-to-day writes use the device key; the master
signs only `device-add`, `rotation` and `revocation`.

A stolen laptop costs one device, not the account: `identity device-revoke`
names the key and the seq it died at, and anything it signs past the cutoff
is dropped on verify. Everything it signed while it was yours keeps
verifying — the cutoff is now, not zero.

### Rotation, revocation, recovery

- **Rotation** hands signing to a successor key. Old keys go quiet: anything
  the old master signs after the rotation is refused.
- **Revocation** (`revocation`, or `device-revoke` for devices) names a key
  and a cutoff seq.
- **Recovery** is social, for losing every key. A successor key announces
  itself in a `recovery` record carrying endorsements — signatures from a
  majority of the friends on the feed, at least one. Two rules keep the
  mechanism from laundering theft:
  1. The successor signs the announcement itself. A recovery signed by the
     *old* master is the thief choosing their own successor, and is refused.
  2. Only friends with tenure vote: added at least `RECOVERY_TENURE` (5) of
     the owner's own records ago. Keys stuffed during the attack cannot elect
     the attacker; long-standing friends can always hand the name back.

After a recovery the device list and revocations reset — the new owner starts
clean, and the old master is dead.

### What theft can and cannot do

Old versions are signed and already replicated by friends, so an attacker
cannot rewrite history — only append junk until a revocation spreads. The
race is revoking before the junk reaches your follows, and with follow-gated
replication the blast radius is exactly that wide. Fork detection is free:
two records, same author and seq, different hashes, and the feed shows
"possibly compromised" instead of picking one.

## Records

Every record, all kinds:

    { author, signer, seq, prev, kind, body, sig }

- `author` — the feed's key, constant from seq 1. Rotation hands the
  *signing* to a new key; it never renames the feed.
- `signer` — the current owner, the successor, or an authorised device.
- `seq` — 1, 2, 3, …, no gaps.
- `prev` — the hash of the previous record (`0`*64 for seq 1).
- `kind`, `body` — what happened (below).
- `sig` — Ed25519 over domain-separated canonical bytes:
  `ricespace-p2p-v1 || author || seq || prev || kind || canonical_json(body)`.

Canonical JSON: hash keys sorted by string form, no whitespace, UTF-8. The
record's address is the SHA256 of its canonical form, signature included.

### Kinds

| Kind | Body | Who signs |
|---|---|---|
| `page` | `document` (≤ 200 000 bytes) + `files` (per-file SHA256) | device |
| `rice` | facts inline (`title`, `summary`, `details`, named facts), shots as `{caption, sha256}` | device |
| `lists` | `blurbs`, `demos`, `builds`, `links`, `friends` — entries inline | device |
| `assets` | `files`: `{name, sha256, kind, bytes}` — pictures by content hash, bytes fetched separately | device |
| `reaction` | `target_feed`, `target_hash`, `like`/`dislike`/`none` | device |
| `comment` | `parent_hash`, `text` (≤ 1000 chars, plain text like every wall) | device |
| `friend` | `peer`, `petname`, `add`/`remove` | device |
| `device-add` | `device` | **master only** |
| `device-revoke` | `device`, `cutoff_seq` | **master only** |
| `rotation` | `new_master` (must move forward) | **master only** |
| `revocation` | `subject`, `cutoff_seq` | **master only** |
| `tombstone` | optional `message` (a line) — the goodbye; nothing after it verifies | device |
| `recovery` | `new_master` + `endorsements` | the successor itself |

Account management is the owner's alone: a `device-add` signed by a device
key is the theft working, not the owner, and is refused.

### Verification

Walk in order; check every link: shape, signature, seq, prev, signer
authorisation, owner-only kinds, recovery quorum and tenure. A fork marks the
feed compromised rather than picking a side. A forked feed is never clean,
even when every record in it verifies alone. Anything after a tombstone is
refused — the goodbye is the feed's last word.

## Storage

Per workstation, under `~/.local/share/ricespace/feeds/<master-pub-hex>/`
(`RICESPACE_STORE` overrides; `XDG_DATA_HOME` is honoured): records as
`00000001.json`, one file each, plus `assets/<sha256>` for pictures.

- Own feed: everything. Followed feeds: full replicas. Everything else: nothing.
- Owner-offline pages load from any mutual follow.
- Assets transfer only by explicit hash request, are verified by hash on
  arrival, and stop at 200 MB of *others'* pictures. Your own are always kept —
  the cap mirrors the site's `STORAGE_LIMIT` idea, enforced at fetch.

## Sync

TLS (default port 7676, ephemeral self-signed Ed25519 certs minted from device
keys), newline-delimited JSON:

    HELLO(node) → HAVE(feed) → HAVE(feed, seq) → WANT(feed, from, limit) → GIVE(records)
    NEED(hashes) → HAVE(sizes) → FETCH → bytes

The puller pins the serving node's key: the cert must carry a key of the
account at the dialed address (live device learned from its feed, else its
master key), or the session dies before HELLO. Replica pulls pin the serving
node, not the wanted feed — pinning the feed would break the owner-offline
path, where a mutual serves records its own key never signed. Serving is open
to any well-formed cert, because records are public data and every one is
signature-verified by the puller; authentication lives on the dial side and in
the records, and a server that demanded to know every puller could never meet
a new follower.

Per-feed HAVE means each side learns only the seqs of feeds the other names —
never a full inventory up front (the old HELLO carried the whole follow graph;
it no longer does). GIVE batches cap at 200 records; a session moves at most
5 000 records / 256 MB before it is cut. The server holds 32 connection slots
and 20 dials per address per minute. Connect timeout 5 s, read timeout 15 s,
and a line past 256 KB kills the session.

Peers are manual — `peer add <key> <name> --at host:port` — plus a UDP
broadcast LAN beacon (port 7677, every 10 s; same room just works,
`--no-lan` to disable). There is no DHT. NAT traversal without a public peer
is impossible; any design claiming otherwise is hiding a relay.

## Rendering

`ProfileMarkup` and `PageCss` are unchanged — they are the render spec every
node runs locally. Remote pages render read-only through the same cleaners:
a `<script>` is gone in the replica because it is gone on the site, and a
`<marquee>` runs because it runs. One lazy renderer is how XSS ships.

## The app as a node

The Rails app is *your* node. It holds verified replicas (`peers`,
`peer_records` — raw replicated truth; no `Rating`/`Comment` row is ever
created for remote content), renders them read-only at `/peers`, computes its
own front-page ranking from replicated reactions by the same rule
(most-reacted first), and signs your reactions and comments into your feed
when its node-device is authorised. Local writes publish opportunistically;
`folder sign --all` is the authoritative publish.

### Authorisation flow

1. The operator generates a device key (`peer keygen`), stores the secret in
   `RICESPACE_NODE_SECRET_FILE` (0600), and the node's `/peers` page shows
   the public half.
2. The owner links their account in the studio (*Your feed on the network* —
   paste the master key from `identity show`). The studio reports whether the
   node may sign yet.
3. The owner authorises the node from the machine holding the master:
   `identity device-add <node public key>`. Synced on the next import, the
   node signs from then on. `device-revoke` ends it.

Without authorisation the node refuses rather than forges — reacting shows
"this node may not sign for your account yet".

## Threat model

What we assume an attacker can do, and what stops them:

- **Forge records.** Stopped by signatures: every record verifies by author
  key, seq, prev and signer authorisation. A fork flags the feed compromised
  rather than picking a side.
- **Read the wire.** Stopped by TLS: ephemeral self-signed certs, pinned on
  the dial side. A passive observer sees ciphertext and endpoints, not feeds
  or follow graphs (HAVE is per-feed, post-pinning).
- **Impersonate a node.** Stopped by pinning: the cert must carry a key of
  the account at the dialed address. A valid cert for the wrong key dies
  before HELLO.
- **Flood a node.** Bounded, not prevented: 32 connection slots, 20 dials per
  address per minute, 256 KB lines, 5 000 records / 256 MB per session, 200
  MB of others' pictures. Past any of them the session dies.
- **Steal a device.** Bounded by revocation: one `device-revoke` with a
  cutoff, and everything past it drops on verify. Old records keep verifying.
- **Steal the identity file.** Hinges on the passphrase: secrets rest in
  scrypt + AES-256-GCM envelopes (N=2¹⁵, r=8, p=1), and old PEM envelopes
  read back for migration but are never written. A weak passphrase is the
  whole lock — `identity create`/`join` warn below the floor (20 characters,
  three of four classes).
- **Steal the node secret.** Total for that node: it signs for every linked
  account. The file is refused unless mode 0600 or stricter. Operators who
  share one node-device across accounts accept this blast radius knowingly.
- **Spoof the LAN beacon.** Possible today: UDP 7677 carries no signature, so
  a fake announcement points victims at attacker addresses. Contained: the
  TLS pin still has to pass, and records still have to verify — worst case is
  eclipse plus metadata, never forgery. Signed beacons are the outstanding fix.
- **Social-engineer a recovery.** Slowed, not stopped: only friends with
  tenure (5 of the owner's records) vote, and the successor announces itself
  (a recovery signed by the old master is refused). A patient attacker who
  befriended early plus apathetic friends can still take over — and it is
  irreversible. Keep people you actually know on the list.
- **Rewrite your own past.** Caught, not prevented: anyone holding an old
  version proves the fork. Tamper-evident, not tamper-proof.
- **Shut the network down.** Impossible by design: no centre, no registry, no
  keyserver. Killing any node removes its replicas and nothing else.

What we explicitly do not cover: endpoint compromise beyond the key files
(root on your machine is root on your account), paper-backup opsec (a
photographed `identity backup` is the account, gone), traffic-analysis
resistance (endpoints and timing are visible), and spam beyond follow-gating.

## What this does not do

Global search, stranger discovery while offline, human-readable global names,
spam prevention beyond follow-gating (unfollowed keys never reach disk).
Rate limits stay a central-server tool; out here the follow list is the limit.
An indexer — a server by another name — comes only if this proves
insufficient.
