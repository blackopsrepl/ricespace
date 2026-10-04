# Internet networking

The design for the networking release (v0.6.0). Read this before touching
`cli/lib/ricespace/net/`. One implementable design, not a catalogue: every
rejected alternative is one line, then the choice stands.

Two facts decide everything below:

1. Account keys are Ed25519 — the same curve the Mainline DHT's mutable slots
   (BEP44) are signed with. Discovery reuses existing key material with zero
   new cryptography.
2. Sync is TLS-over-TCP with device-key pinning. Nothing in UDP hole punching
   helps a TCP transport — a "successful" UDP traversal followed by a TCP
   connect the NAT drops is theatre. Traversal here is TCP or relay, or the
   wire protocol changes. It does not change.

Constraint: the project owner operates no server. Anything below that smells
like one — a bootstrap list we must keep alive, a relay fleet — is either
peer-run or it does not exist.

Live evidence (all probes run 2026-10-04 from residential egress, no IPv6):

- STUN binding to `stun.l.google.com:19302` answers. UDP egress is open.
- Real BEP5 pings answered by `dht.transmissionbt.com:6881` and
  `dht.libtorrent.org:25401`. `router.bittorrent.com`, `router.utorrent.com`
  and `bootstrap.jami.net` timed out from here on both ports tried.
- `Sync::Session#serve_loop` has no `else` branch: unknown message types are
  a no-op, so new wire messages are backward compatible with v0.5.0 nodes.

## 1. Chosen stack

| Problem | Mechanism | Protocol / code | Why this one |
|---|---|---|---|
| Internet discovery | Mainline DHT, BEP5 routing + BEP44 mutable slots | stdlib KRPC client, `net/bencode.rb` + `net/dht.rb` | Peer-run by millions of BitTorrent users; BEP44 was written as a general KV store, not only for torrents. A RiceSpace-specific DHT would need its own bootstrap fleet — owner infrastructure by another name. |
| Endpoint records | One mutable slot per device, salt `ricespace-ep-v1` | `net/endpoint.rb`, signed with `Canonical.signing_bytes` (kind `endpoint`) | Master stays offline: each device publishes its own slot with a key it already holds online. Multiple devices fall out free. |
| Candidate addresses | UPnP IGD port mapping + NAT-PMP + STUN observation + manual `--at` + LAN beacon (kept) | stdlib SSDP/SOAP (`net/upnp.rb`), 12-byte NAT-PMP (`net/natpmp.rb`), RFC5389 binding client (`net/stun.rb`) | All stdlib-sized protocols; no gems, gemspec stays dependency-free. |
| NAT characterisation | STUN mapping-behaviour test (two servers) + UPnP presence | `net/nat.rb` | Best-effort labels, always stating how determined. Never equated with reachability. |
| Traversal | Unchanged TCP + TLS + pinning; dial ladder direct → DHT-found → friend relay → open rendezvous | `sync.rb` extensions + `net/relay.rb` | No UDP punching (wrong transport). TCP simultaneous-open was cut: it fails exactly where it is needed (symmetric NAT), and untestable code is not a rung. |
| Friend fallback | Opt-in TCP byte-bridge through a followed reachable peer | `BRIDGE` wire messages, `peer serve --relay` | Forwards bytes, not records: end-to-end TLS and pinning survive the relay untouched. The relay cannot read or forge. |
| Open rendezvous | Volunteer relays splice two strangers by single-use ticket | `ALLOC`/`JOIN`/`PAIRED` + BYTES shuttle, `peer serve --relay-open`, `net wait` | Both sides dial out (no NAT objects); no prior contact, no shared friend. Shipped list starts empty — volunteers PR themselves in, same as seeds. |
| Owner-offline serving | Unchanged replica serving | existing `serve_want` path | Already the delivery story; friends carry copies. |

## 2. Dependency and interoperability evidence

- DHT routers: three shipped (`dht.transmissionbt.com:6881`,
  `router.utorrent.com:6881`, `dht.libtorrent.org:6881`), all long-lived
  public infrastructure. Probes above confirm two answer from ordinary
  residential egress. Rotation: a router that fails ping is skipped and the
  next tried; a router entry is replaced by DHT-learned neighbours, so the
  bootstrap contact decays to zero steering within minutes of joining.
- BEP44 `get`/`put` interop: unrelated nodes do not "relay our data" as a
  favour — they implement the same BEP they have implemented for a decade.
  Our `v` is a byte string under 1000 bytes; nodes that reject it are normal
  DHT churn, handled by the standard 8-way `put` replication and majority
  `get`. A client that drops BEP44 traffic entirely is just a dead node to us.
- Storage format: the BEP44 signature covers `salt + seq + bencoded v`. We
  bencode our endpoint JSON deterministically (sorted keys) so the bytes we
  sign are the bytes any client stores. Test vectors: BEP44 §test 1/2 vectors
  are asserted in `cli/test/net_bep44_test.rb` against our bencoder.
- Salt `ricespace-ep-v1`: target = SHA1(pub || salt). Salted slots keep one
  master identity able to address future slot kinds without key reuse
  collisions.
- RPC id: random 20 bytes per process (never the account key — DHT node id is
  routing position, not identity; advertising `SHA1(pubkey)` as a node id
  would link identity to routing traffic for free).
- Libraries: none. Bencode (~40 lines), KRPC over UDPSocket, STUN (20-byte
  header + XOR-MAPPED-ADDRESS parse), NAT-PMP (12-byte request), UPnP
  SSDP+SOAP over stdlib net/http — all written once, all tested against a
  loopback fake. If a library materially improved correctness we would take
  it; nothing in this list is hard enough to justify one (bencode especially:
  taking a gem for 40 lines would be dependency theatre).

## 3. First-install bootstrap sequence

1. `ricespace identity create` → `ricespace net up` (new command, §8).
2. `net up` sends BEP5 pings to the three routers in order, first answer wins
   (~seconds in the common case, bounded by 3 × 4 s timeouts).
3. `find_node(self-id)` walk seeds the routing table; table persists to
   `~/.config/ricespace/dht.json` (0600) between runs.
4. STUN binding learns the observed external address; UPnP/NAT-PMP attempts a
   mapping. Results feed the endpoint publication, labelled by provenance.
5. `peer bootstrap` follows the shipped seed keys, then resolves them: LAN
   map → manual `--at` → DHT endpoint slots. Sync proceeds over whatever
   resolves. Seeds with no address and no slot are reported, not chased.
6. The node publishes its own endpoint slot and starts hourly republication
   while `peer serve` runs.

Bootstrap outage behaviour: if all three routers are silent, the node keeps
its persisted routing table and retries with exponential backoff (max 5 min
interval); everything local — LAN sync, manual addresses, gossip — keeps
working. A fresh install during a total bootstrap outage cannot discover; it
says exactly that ("no discovery contact — add an address manually or wait
for routers"), and the manual path is unchanged. Bootstrap contact is routing
help, not control: routers learn nothing about feeds, follows or keys (node
ids are random), and no router can grant, deny or observe a follow.
## 4. Endpoint announcement and verification format

Published as the BEP44 `v` (bencoded dict, ≤ 1000 bytes), signed by the
**device key**:

```
{ "ep": 1,                       # format version
  "node": "<master-pub>",        # feed this device belongs to
  "device": "<device-pub>",      # slot owner, must equal BEP44 k
  "addrs": ["h:p", ...],         # ≤ 4, observed or mapped only
  "at": <unix>,                  # publication time
  "exp": <unix>,                 # at + 7200 (2 h, DHT republication period)
  "relay": ["h:p", ...] }        # ≤ 2 consenting bridges that carry this feed
```

Signature: `Keys.sign(device_priv, Canonical.signing_bytes(author: node,
seq: at, prev: device, kind: "endpoint", body: {...without sig...}))` and the
64-byte hex `sig` rides inside `v`. Reuses the feed signature domain — one
signature scheme for everything.

Verification (every consumer, every time):

1. `device == k` of the slot, else drop (slot squatting).
2. `Keys.verify(device, sig, signing_bytes(...))`, else drop.
3. The device must be authorised on the feed **at `at`**: replay `verify_chain`
   of the held feed and require `devices[device].added` with no revocation
   cutoff ≤ `at`, or master == device, or current owner == device. A signed
   endpoint from a never-authorised key is gossip noise, not an address.
4. `exp` in the future and `at` within ±600 s of now, else stale (replay).
5. `addrs` parse as `host:port`, ≤ 4 entries, no `0.0.0.0`, no port 0.
   Private-range addresses are kept but flagged `lan-only`.
6. `relay` entries parse the same way, ≤ 2.

Recorded into `peers.json` as `{pub => {addrs, relay, ep_at, ep_exp}}`; gossip
`ADDR` messages carry them with the same checks; unverified endpoint data
never creates follows and quarantined feeds never render (unchanged rule).

## 5. Direct connection and fallback state machines

Dial ladder per follow (each rung bounded by `CONNECT_TIMEOUT`, whole ladder
bounded by 60 s):

```
LAN map → manual --at → DHT addrs (in-slot order) → relay bridges
  found        ok       ok                     ok
   │            │        │                      │
   └──── PIN FAIL → next rung (a pin failure never falls back to
                   unauthenticated — it fails the rung, not the ladder)
```

States per follow: `unknown → direct | assisted | unreachable`. `peer status`
(new, §8) shows the state, the working rung, `ep_at` age, NAT label, and last
successful sync. Every transition is printed once; steady-state repeats are
quiet.

Relay bridge protocol (new wire messages, backward compatible — v0.5.0 nodes
ignore them as no-ops):

```
BRIDGE { "to": "<target-device-pub>", "via": "<relay-addr>" }
  → BRIDGED { "session": "<id>" } | NOROUTE {}
BYTES  { "session": "<id>", "blob": "<raw TLS bytes, base64>" }
  → BYTES { "session": "<id>", "blob": "<reply bytes>" }
HANGUP { "session": "<id>" }
```

The relay opens no TLS itself: it copies opaque blobs between two
already-TLS-speaking sockets, each still pinned end-to-end. A malicious relay
sees ciphertext, timing and sizes — documented in §7 — and can drop traffic
(the ladder then tries the next rung). Sessions cap at 32 MB moved and 10 min
lifetime; one session per caller per target; friend bridges are consent-only
(`peer serve --relay`, off by default) so no user becomes an involuntary
public proxy.

Open rendezvous (`ALLOC`/`JOIN`/`PAIRED`, `peer serve --relay-open`): both
strangers dial the relay out (nothing to punch through); the relay shuttles
BYTES frames between the two control connections while the end-to-end TLS
handshake runs *inside* them — waiter in server role, joiner in client role,
both pinned to each other's device keys. Tickets are 64-bit, single-use,
5 min expiry, signalled through the waiter's own signed endpoint slot (the
`ticket` field names the relay, the secret and the peer). The joiner's
control leg to a stranger relay is explicitly unpinned (`:none` — opt-in,
never default); all trust rides the end-to-end pin plus the ticket secret.
Abuse bounds: ≤ 8 sessions, ≤ 64 tickets, same 32 MB / 10 min caps; a hostile
relay sees ciphertext and timing and can drop — the ladder moves on.

## 6. Authorization, expiry and revocation rules

- Endpoint slots authenticate against feed history, not against "any
  self-generated key": the device must be authorised on the feed the slot
  claims (`device-add` present and unrevoked at publication time, or master,
  or post-rotation owner).
- `device-revoke` and `rotation`/`recovery` invalidate future slots from the
  old key immediately; in-flight `addrs` entries expire by `exp` (≤ 2 h) and
  are re-verified against fresh chain state on every sync.
- Sequence: BEP44 `seq` is wall-clock publication time; storing nodes keep
  the higher `seq`, so a republish always wins and a replayed slot loses.
- First contact (no feed history yet): the slot's device may pin the TLS
  session provisionally — authentication of the binding, not authorisation of
  the device. Records fetched over it still verify against the master key
  received out-of-band; a feed that never authorised the slot's device yields
  zero merged records (unauthorised signers fail `verify_chain`), and the
  provisional pin is then dropped. Gossip `ADDR` entries may carry endpoint
  data with the same checks; unverified endpoint data is stored nowhere.
- Revocation of a *relay*: dropping `--relay` stops advertising; existing
  sessions drain to their caps. A relay that turns hostile is contained by
  the byte cap, the per-caller session limit, and end-to-end TLS — it was
  never trusted with content.
## 7. Resource budgets and privacy implications

Budgets (constants beside the code, all tested):

- DHT: ≤ 64 in-flight KRPC queries, 4 s per-query timeout, routing table ≤ 128
  nodes, `put` replication factor 8, hourly republication, slot ≤ 1000 bytes.
- UPnP/NAT-PMP: one mapping attempt per `peer serve` start, 10 s bounded; lease
  requested 3600 s, released on exit.
- Relay: 32 MB per bridged session, 10 min max lifetime, ≤ 8 concurrent
  sessions per servant, budged inside the existing 32 connection slots
  (a bridge occupies one slot per leg).
- Endpoint store: ≤ 4 addrs + ≤ 2 relays per follow; `peers.json` growth is
  O(follows), unchanged shape plus three fields.

Privacy (stated honestly, shown to the user by `peer status --privacy`):

- DHT slots are public: `(master-pub, device-pub, addrs, relay-addrs)` is
  readable by anyone who derives the target. Discovery metadata is connection
  metadata — it says where to dial, never what the feed contains, who follows
  whom, or anything past the seq that gossip already leaks.
- Mitigations: slots carry no petnames, no follow lists, no seq numbers;
  node ids are random per process; HAVE stays per-feed post-pinning.
- Adversarial catalogue: **poisoning** (bad slots fail signature/device
  checks — stored nowhere); **eclipse/Sybil** (8-way replication + majority
  `get`; a determined eclipse delays but the ladder falls back to manual/LAN);
  **replay** (±600 s window + `exp` + seq-wins); **malicious endpoints**
  (pin failure fails the rung; an endpoint is never proof the host consents —
  unsolicited traffic to a stranger's address is their firewall's call, and
  the dialer learns nothing from a refusal); **private-network probing** (DHT
  addrs flagged `lan-only` are never auto-dialled off-LAN); **resource
  exhaustion** (all caps above; DHT queries never amplify — one query in,
  one bounded response out); **relay abuse** (consent-only, byte-capped,
  content-opaque).

What remains impossible: nothing short of a network partition. Two
outbound-only peers with no mutual friend sync via TCP simultaneous-open
(where the NATs allow) or via an open rendezvous relay neither has met
before. The ladder (§5) always has a rung left; `unreachable` is reported
only when every rung provably failed, with which one and why.

Correction to an earlier claim: BitTorrent does not connect two unreachable
peers with no third party either — it punches permissive NATs via
tracker/DHT rendezvous and stalls on symmetric↔symmetric. The difference is
not magic, it is one more rung (simultaneous-open) plus relays that do not
require prior friendship. Both are below; both are peer-run.

## 8. CLI surface

Normal flow: `identity create` → `net up` → `peer add <key> <name>` →
`peer sync`. No routine IP exchange: addresses resolve via LAN → DHT →
gossip, and `peer sync` walks the ladder per follow.

- `net up` — join discovery (DHT bootstrap, STUN/NAT probe, publish slot,
  show reachability label). `--no-publish` joins without publishing.
- `net down` — release mappings, stop republication.
- `peer serve [--relay|--relay-open]` — as before, plus friend bridging
  (`--relay`) or open stranger rendezvous by ticket (`--relay-open`).
- `net wait <who> --at relay:port` — the unreachable node that wants to be
  found: ALLOCs a ticket, publishes it in its own slot, serves when they JOIN.
- `peer status [name|key]` — discovery state, direct/punched/assisted path,
  reachability label + how determined, last successful sync, actionable
  failures. `--privacy` explains what the slots expose.
- `peer sync` — unchanged flags; walks the ladder instead of only stored
  addrs. Manual `--at` stays as the advanced escape hatch and always wins
  rung 2.
- Laptop sleep / Wi-Fi change / CGNAT reconnect: `net up` re-probes on each
  invocation; `peer serve` re-publishes hourly and on socket errors; stale
  slots expire by `exp`; the ladder re-resolves every sync, so a changed
  endpoint is found without manual updates.

## 9. Migration from v0.5.0

- `peers.json` gains three optional fields per follow (`relay`, `ep_at`,
  `ep_exp`); old files load unchanged.
- Wire: three new message types (`BRIDGE`/`BYTES`/`HANGUP`); v0.5.0 nodes
  ignore them, v0.6 nodes sync with v0.5 nodes over every path that already
  worked.
- `Record::KINDS` is untouched. Endpoint signatures reuse the
  `Canonical.signing_bytes` domain with kind `"endpoint"` as a separator only
  — those byte strings are never records, never touch feeds, and Rails import
  never sees them.
- `peer bootstrap` keeps following seeds, then resolves via the ladder.
- CLI stays stdlib-only; gemspec unchanged.

## 10. Acceptance tests and implementation order

Order: bencode → KRPC/DHT → endpoint sign/verify → STUN/UPnP/NAT-PMP →
dial ladder + relay → CLI (`net up/down`, `peer status`) → docs.

1. BEP44 test vectors (§2) pass against our bencoder.
2. Authenticated discovery between independently initialized peers (loopback
   DHT fake + real sync): A follows B's key only, learns B's new endpoint
   from the slot, syncs.
3. Changed endpoint without manual updates: B re-publishes, A resolves on
   next sync.
4. Expired, forged (wrong device), revoked-device and never-authorised slots
   are all rejected and stored nowhere.
5. Fresh-install bootstrap (routers stubbed) and total-outage behaviour
   (honest "no discovery contact", local paths keep working).
6. Direct replication plus relay-bridged replication through a consenting
   bridge, with TLS pinning verified end-to-end and the relay seeing only
   ciphertext. Plus open-rendezvous replication between two strangers through
   a ticket relay neither has met (loopback-proven, 3 records, pinned both
   legs).
7. Quarantine/follow isolation unchanged: hints never become follows.
8. Rails `PeerSync.import_store` imports a relay-fetched feed (DB-backed,
   in `test/models/`).
9. Bounded failure: caps enforced (32 MB session, 8 concurrent, query
   timeouts), cleanup verified (mappings released, sessions drained).

Implementation lives in `cli/lib/ricespace/net/` (`bencode.rb`, `dht.rb`,
`endpoint.rb`, `stun.rb`, `upnp.rb`, `natpmp.rb`, `nat.rb`, `relay.rb`),
tested by `cli/test/net_bep44_test.rb` + `cli/test/net_discovery_test.rb`,
both registered in `config/ci.rb`.
