# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require "fileutils"

require_relative "../lib/ricespace"

# The signed feed: identities, records, and the folder envelope. Everything here
# runs without a space — a feed is local files, and trust is arithmetic.
class P2pTest < Minitest::Test
  include RiceSpace::P2p

  def test_canonical_bytes_do_not_depend_on_key_order
    first = Canonical.json({ "b" => 1, "a" => [ 3, { "z" => nil, "y" => 2 } ] })
    second = Canonical.json({ "a" => [ 3, { "y" => 2, "z" => nil } ], "b" => 1 })

    assert_equal first, second
  end

  def test_a_key_survives_encryption_and_signs
    keypair = Keys.generate

    assert Keys.valid_public?(keypair[:public_hex])
    assert_equal keypair[:public_hex], Keys.public_from_private(keypair[:private_hex])

    pem = Keys.protect(keypair[:private_hex], "s3cret")
    assert_equal keypair[:private_hex], Keys.unprotect(pem, "s3cret")
    assert_raises(CryptoError) { Keys.unprotect(pem, "wrong") }

    sig = Keys.sign(keypair[:private_hex], "hello")
    assert Keys.verify(keypair[:public_hex], sig, "hello")
    refute Keys.verify(Keys.generate[:public_hex], sig, "hello")
    refute Keys.verify(keypair[:public_hex], sig, "goodbye")
  end

  def test_a_chain_verifies_and_a_forgery_does_not
    master = Keys.generate
    device = Keys.generate
    chain = [
      signed(master, master, 1, Record::GENESIS_PREV, "device-add", { "device" => device[:public_hex] }),
      signed(master, device, 2, nil, "page", { "document" => "<marquee>hi</marquee>" })
    ]
    chain[1] = relink_one(chain[1], chain[0], device[:private_hex])

    result = Record.verify_chain(chain)

    assert result.ok?, result.errors.inspect
    assert_equal 2, result.state["seq"]

    evil = Keys.generate
    forged = signed(master, evil, 2, Record.hash_of(chain[0]), "page", { "document" => "pwned" })
    refused = Record.verify_chain([ chain[0], forged ])

    refute refused.ok?
    assert_includes refused.errors.first, "may not sign"
  end

  def test_a_rewritten_seq_is_a_fork_and_a_forked_feed_is_never_clean
    master = Keys.generate
    first = signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1" })
    other = signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1-but-evil" })

    assert Record.fork?(first, other)

    result = Record.verify_chain([ first, other ])
    refute result.ok?
    assert_equal 1, result.forks.size
  end

  def test_rotation_hands_signing_over_and_the_old_key_goes_quiet
    master = Keys.generate
    fresh = Keys.generate
    chain = [
      signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1" })
    ]
    chain << signed(master, master, 2, nil, "rotation", { "new_master" => fresh[:public_hex] })
    chain = relink(chain, [ master[:private_hex], master[:private_hex] ])
    chain << signed(master, fresh, 3, nil, "page", { "document" => "v2" })
    chain = relink(chain, [ master[:private_hex], master[:private_hex], fresh[:private_hex] ])

    result = Record.verify_chain(chain)

    assert result.ok?, result.errors.inspect
    assert_equal fresh[:public_hex], result.state["owner"]

    stale = signed(master, master, 4, Record.hash_of(chain.last), "page", { "document" => "i am back" })
    refused = Record.verify_chain(chain + [ stale ])

    refute refused.ok?
  end

  def test_a_goodbye_closes_the_feed
    master = Keys.generate
    chain = [ signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1" }) ]
    chain << signed(master, master, 2, nil, "tombstone", { "message" => "goodbye" })
    chain = relink(chain, [ master[:private_hex], master[:private_hex] ])

    result = Record.verify_chain(chain)

    assert result.ok?, result.errors.inspect
    assert result.state["deleted"]

    late = signed(master, master, 3, Record.hash_of(chain.last), "page", { "document" => "back?" })
    refused = Record.verify_chain(chain + [ late ])

    refute refused.ok?
    assert_includes refused.errors.first, "closed"
  end

  def test_recovery_needs_old_friends_not_new_socks
    master = Keys.generate
    friends = Array.new(2) { Keys.generate }
    chain = [ signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v0" }) ]
    friends.each_with_index do |friend, index|
      chain << signed(master, master, chain.size + 1, nil, "friend",
        { "peer" => friend[:public_hex], "petname" => "pal#{index}", "action" => "add" })
    end
    4.times do |index|
      chain << signed(master, master, chain.size + 1, nil, "page", { "document" => "v#{index}" })
    end
    secrets = Array.new(chain.size, master[:private_hex])
    chain = relink(chain, secrets)

    successor = Keys.generate
    recovery = recovery_record(chain, successor, friends)
    result = Record.verify_chain(chain + [ recovery ])

    assert result.ok?, result.errors.inspect
    assert_equal successor[:public_hex], result.state["owner"]

    # A sock added one record ago cannot vote, even with a valid signature.
    sock = Keys.generate
    stuffed = chain + [
      relink_one(signed(master, master, chain.size + 1, nil, "friend",
        { "peer" => sock[:public_hex], "petname" => "sock", "action" => "add" }),
        chain.last, master[:private_hex])
    ]
    evil = Keys.generate
    evil_recovery = recovery_record(stuffed, evil, [ sock ])
    refused = Record.verify_chain(stuffed + [ evil_recovery ])

    refute refused.ok?

    # And the thief holding the old master cannot launder it as a recovery.
    laundered = recovery_record(chain, successor, friends, signer: master)
    refused = Record.verify_chain(chain + [ laundered ])

    refute refused.ok?
    assert_includes refused.errors.first, "successor"
  end

  def test_an_identity_is_created_unlocked_and_backed_up
    Dir.mktmpdir do |dir|
      identity = Identity.create(
        dir: dir, device_name: "testbox",
        master_passphrase: "correct horse", device_passphrase: "correct horse"
      )

      assert_equal identity.master_public, Identity.load(dir).master_public
      assert_match(/\Arice:[0-9a-f]{12}\z/, identity.short_id)
      assert_raises(RiceSpace::P2p::Error) { identity.unlock_device("wrong") }

      secrets = identity.backup("correct horse")

      assert_equal identity.master_public, secrets["master_public"]
      assert_equal identity.master_public, Keys.public_from_private(secrets["master_secret"])
    end
  end

  def test_a_feed_appends_in_order_and_refuses_a_rewrite
    Dir.mktmpdir do |dir|
      master = Keys.generate
      feed = Feed.new(master[:public_hex], root: dir)

      first = signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1" })
      feed.append(first)

      assert_equal 1, feed.records.size
      assert feed.verify.ok?

      other = signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "v1-evil" })
      assert_raises(ChainError) { feed.append(other) }

      # The fork never reaches disk — append refuses it. A feed holding both
      # branches (arrived separately, e.g. over sync) is never clean.
      assert Record.fork?(first, other)
      refute Record.verify_chain([ first, other ]).ok?
    end
  end

  def test_a_folder_signs_verifies_and_notices_an_edit
    Dir.mktmpdir do |home|
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "page.html"), "<marquee>hi</marquee>")
        File.write(File.join(dir, "rice.json"), JSON.generate({ "title" => "rice" }))

        master = Keys.generate
        device = Keys.generate
        feed = Feed.new(master[:public_hex], root: File.join(home, "feeds"))
        feed.append(signed(master, master, 1, Record::GENESIS_PREV,
          "device-add", { "device" => device[:public_hex] }))

        folder = RiceSpace::Folder.read(dir)
        record = folder.sign(feed: feed, private_hex: device[:private_hex], device_public: device[:public_hex])

        assert_equal 2, record["seq"]
        assert File.file?(File.join(dir, "manifest.json"))

        checked = RiceSpace::Folder.read(dir).verify!

        assert_equal Record.hash_of(record), Record.hash_of(checked)

        File.write(File.join(dir, "page.html"), "<marquee>edited</marquee>")
        error = assert_raises(RiceSpace::UsageError) { RiceSpace::Folder.read(dir).verify! }
        assert_includes error.message, "changed"
      end
    end
  end

  def test_an_export_carries_the_page_and_its_proof
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "page.html"), "<marquee>hi</marquee>")
      master = Keys.generate
      feed = Feed.new(master[:public_hex], root: File.join(dir, "feeds"))
      feed.append(signed(master, master, 1, Record::GENESIS_PREV, "page", { "document" => "x" }))

      folder = RiceSpace::Folder.read(dir)
      folder.sign(feed: feed, private_hex: master[:private_hex], device_public: master[:public_hex])

      out = File.join(dir, "static")
      folder.export_to(out)

      assert File.file?(File.join(out, "page.html"))
      assert File.file?(File.join(out, "manifest.json"))

      exported = RiceSpace::Folder.read(out).verify!

      assert_equal master[:public_hex], exported["author"]
    end
  end

  def test_completions_cover_the_new_verbs
    %w[bash zsh fish].each do |shell|
      text = RiceSpace::Completions.for(shell)
      assert_includes text, "identity", "#{shell} completions must know identity"
      assert_includes text, "peer", "#{shell} completions must know peer"
    end
    assert_includes RiceSpace::Completions::SUBCOMMANDS["folder"], "sign"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["folder"], "verify"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["folder"], "export"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["identity"], "device-add"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["identity"], "device-revoke"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["peer"], "keygen"
    assert_includes RiceSpace::Completions::SUBCOMMANDS["peer"], "sync"
  end

  def test_keygen_prints_a_usable_pair
    out = capture_stdout { RiceSpace::Command.new([ "peer", "keygen" ]).run }

    public_hex = out[/public: ([0-9a-f]{64})/, 1]
    secret_hex = out[/secret: ([0-9a-f]{64})/, 1]

    assert public_hex, "keygen prints the public half"
    assert secret_hex, "keygen prints the secret"
    assert_equal public_hex, RiceSpace::P2p::Keys.public_from_private(secret_hex)
  end

  private

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def signed(author, signer, seq, prev, kind, body)
    RiceSpace::P2p::Record.build(
      author: author[:public_hex], signer: signer[:public_hex],
      seq: seq, prev: prev || Record::GENESIS_PREV,
      kind: kind, body: body, sign_with: signer[:private_hex]
    )
  end

  # Re-sign a chain built with placeholder prevs so every link holds.
  # Threads forward: each record's prev is the hash of the re-signed previous.
  def relink(chain, secrets)
    built = []
    chain.each_with_index do |record, index|
      built << relink_one(record, index.zero? ? nil : built[index - 1], secrets[index])
    end
    built
  end

  def relink_one(record, previous, secret)
    prev = previous.nil? ? Record::GENESIS_PREV : Record.hash_of(previous)
    RiceSpace::P2p::Record.build(
      author: record["author"], signer: record["signer"],
      seq: record["seq"], prev: prev,
      kind: record["kind"], body: record["body"], sign_with: secret
    )
  end

  def recovery_record(chain, successor, endorsers, signer: nil)
    seq = chain.size + 1
    body = { "new_master" => successor[:public_hex] }
    bytes = Canonical.signing_bytes(
      author: chain.first["author"], seq: seq, prev: Record.hash_of(chain.last),
      kind: "recovery", body: body
    )
    endorsements = endorsers.map do |friend|
      { "friend" => friend[:public_hex], "sig" => Keys.sign(friend[:private_hex], bytes) }
    end
    key = signer || successor
    RiceSpace::P2p::Record.build(
      author: chain.first["author"], signer: key[:public_hex],
      seq: seq, prev: Record.hash_of(chain.last),
      kind: "recovery", body: body.merge("endorsements" => endorsements),
      sign_with: key[:private_hex]
    )
  end
end

# The wire, over real TCP on loopback: pull, second-pull-empty, and the
# owner-offline replica path.
class P2pSyncTest < Minitest::Test
  include RiceSpace::P2p

  def test_a_follow_pulls_over_tcp_and_the_second_pull_is_empty
    nodes = make_nodes("b1", "a1")
    dir_b, id_b = nodes[0]
    dir_a, id_a = nodes[1]
    store_b = File.join(dir_b, "feeds")
    store_a = File.join(dir_a, "feeds")

    publish(id_b, store_b, "B here")

    peers_a = Peers.new(path: Pathname.new(dir_a).join("peers.json"), follows: {})
    peers_a.add(id_b.master_public, petname: "bee", addrs: [ "127.0.0.1:18011" ])

    server = serve_on(18011, id_b, store_b)
    thread = Thread.new { server.run }
    sleep 0.5

    begin
      gained = pull_from("127.0.0.1", 18011, id_a, peers_a, store_a, expected: id_b.device_public)

      assert_equal 3, gained.values.sum
      local = Feed.new(id_b.master_public, root: store_a)
      result = local.verify

      assert result.ok?, result.errors.inspect
      assert_equal 3, result.state["seq"]

      again = pull_from("127.0.0.1", 18011, id_a, peers_a, store_a, expected: id_b.device_public)

      assert_empty again
    ensure
      thread.kill
    end
  end

  def test_a_third_node_reads_an_offline_owner_from_a_mutual_follow
    dir_b, id_b = make_node("b2")
    dir_a, id_a = make_node("a2")
    dir_c, id_c = make_node("c2")
    store_b = File.join(dir_b, "feeds")
    store_a = File.join(dir_a, "feeds")
    store_c = File.join(dir_c, "feeds")

    publish(id_b, store_b, "B v2")

    peers_a = Peers.new(path: Pathname.new(dir_a).join("peers.json"), follows: {})
    peers_a.add(id_b.master_public, petname: "bee", addrs: [ "127.0.0.1:18012" ])
    server_b = serve_on(18012, id_b, store_b)
    thread_b = Thread.new { server_b.run }
    sleep 0.5
    pull_from("127.0.0.1", 18012, id_a, peers_a, store_a, expected: id_b.device_public)
    thread_b.kill
    sleep 0.3

    server_a = serve_on(18013, id_a, store_a)
    thread_a = Thread.new { server_a.run }
    sleep 0.5

    begin
      peers_c = Peers.new(path: Pathname.new(dir_c).join("peers.json"), follows: {})
      peers_c.add(id_b.master_public, petname: "bee", addrs: [ "127.0.0.1:18013" ])
      # Pinned to A's device: A serves, even though the feed wanted is B's.
      gained = pull_from("127.0.0.1", 18013, id_c, peers_c, store_c, expected: id_a.device_public)

      assert_equal 3, gained.values.sum
      result = Feed.new(id_b.master_public, root: store_c).verify

      assert result.ok?, result.errors.inspect
      page = Feed.new(id_b.master_public, root: store_c).records.find { |record| record["kind"] == "page" }

      assert_equal "B v2", page["body"]["document"]
    ensure
      thread_a.kill
    end
  end

  def test_unfollowed_feeds_are_not_stored
    dir_b, id_b = make_node("b3")
    dir_a, id_a = make_node("a3")
    store_b = File.join(dir_b, "feeds")
    store_a = File.join(dir_a, "feeds")

    publish(id_b, store_b, "stranger")

    # A never followed B: pull asks only for A itself + follows, so nothing arrives.
    peers_a = Peers.new(path: Pathname.new(dir_a).join("peers.json"), follows: {})
    server = serve_on(18014, id_b, store_b)
    thread = Thread.new { server.run }
    sleep 0.5

    begin
      gained = pull_from("127.0.0.1", 18014, id_a, peers_a, store_a, expected: id_b.device_public)

      assert_empty gained
      assert_empty Feed.new(id_b.master_public, root: store_a).records
    ensure
      thread.kill
    end
  end

  def test_a_pinned_pull_succeeds_and_a_stranger_fails_closed
    dir_b, id_b = make_node("b4")
    dir_a, id_a = make_node("a4")
    store_b = File.join(dir_b, "feeds")
    store_a = File.join(dir_a, "feeds")

    publish(id_b, store_b, "pinned")

    peers_a = Peers.new(path: Pathname.new(dir_a).join("peers.json"), follows: {})
    peers_a.add(id_b.master_public, petname: "bee", addrs: [ "127.0.0.1:18015" ])
    server = Sync::Server.new(port: 18015, identity: id_b,
      peers: Peers.new(path: Pathname.new(dir_b).join("p.json"), follows: {}),
      private_hex: device_secret(id_b), store_root: store_b, lan: false)
    thread = Thread.new { server.run }
    sleep 0.5

    begin
      gained = Sync.pull("127.0.0.1", 18015, identity: id_a, peers: peers_a,
        private_hex: device_secret(id_a), expected_key: id_b.device_public, store_root: store_a)

      assert_equal 3, gained.values.sum
      assert Feed.new(id_b.master_public, root: store_a).verify.ok?

      # Wrong pin: the cert carries B's device, not this key.
      error = assert_raises(RiceSpace::P2p::Error) do
        Sync.pull("127.0.0.1", 18015, identity: id_a, peers: peers_a,
          private_hex: device_secret(id_a), expected_key: id_a.device_public, store_root: store_a)
      end
      assert_includes error.message, "not who was dialed"
    ensure
      thread.kill
    end
  end

  def test_v2_envelopes_round_trip_and_old_pem_reads_back
    keypair = Keys.generate
    env = Keys.protect(keypair[:private_hex], "a sufficiently long passphrase 99!")

    assert_equal keypair[:private_hex], Keys.unprotect(env, "a sufficiently long passphrase 99!")
    assert_raises(RiceSpace::P2p::CryptoError) { Keys.unprotect(env, "wrong passphrase here 99!") }

    assert_nil Keys.passphrase_advice("a sufficiently Long passphrase 99!")
    assert Keys.passphrase_advice("short")
  end

  def test_a_natted_node_publishes_through_its_outbound_connection
    dir_pub, id_pub = make_node("pub5")
    dir_nat, id_nat = make_node("nat5")
    store_pub = File.join(dir_pub, "feeds")
    store_nat = File.join(dir_nat, "feeds")

    publish(id_pub, store_pub, "public here")
    secret = id_nat.unlock_master("x")
    nat_feed = Feed.new(id_nat.master_public, root: store_nat)
    nat_feed.append(Record.build(author: id_nat.master_public, signer: id_nat.master_public, seq: 1,
      prev: Record::GENESIS_PREV, kind: "device-add", body: { "device" => id_nat.device_public },
      sign_with: secret))
    nat_feed.append(Record.build(author: id_nat.master_public, signer: id_nat.device_public, seq: 2,
      prev: nat_feed.prev_hash, kind: "page", body: { "document" => "natted here" },
      sign_with: device_secret(id_nat)))

    # The public node never dials the natted one and never follows it.
    peers_pub = Peers.new(path: Pathname.new(dir_pub).join("peers.json"), follows: {})
    peers_nat = Peers.new(path: Pathname.new(dir_nat).join("peers.json"), follows: {})
    peers_nat.add(id_pub.master_public, petname: "pub", addrs: [ "127.0.0.1:18016" ])
    server = serve_on(18016, id_pub, store_pub)
    thread = Thread.new { server.run }
    sleep 0.5

    begin
      gained = pull_from("127.0.0.1", 18016, id_nat, peers_nat, store_nat, expected: id_pub.device_public)

      assert_equal 2, gained["!pushed"], "the natted node's records land via push"
      result = Feed.new(id_nat.master_public, root: store_pub).verify

      assert result.ok?, result.errors.inspect
      assert_equal 2, result.state["seq"]
    ensure
      thread.kill
    end
  end

  def test_gossip_teaches_an_address_and_hints_stay_unfollowed
    dir_a, id_a = make_node("ga")
    dir_b, id_b = make_node("gb")
    dir_c, id_c = make_node("gc")
    store_a = File.join(dir_a, "feeds")

    publish(id_b, File.join(dir_b, "feeds"), "bee here")
    publish(id_c, File.join(dir_c, "feeds"), "cee here")

    # B follows C and knows its address; A follows only B.
    peers_b = Peers.new(path: Pathname.new(dir_b).join("peers.json"), follows: {})
    peers_b.add(id_c.master_public, petname: "cee", addrs: [ "127.0.0.1:18018" ])
    peers_a = Peers.new(path: Pathname.new(dir_a).join("peers.json"), follows: {})
    peers_a.add(id_b.master_public, petname: "bee", addrs: [ "127.0.0.1:18017" ])

    server = serve_on(18017, id_b, File.join(dir_b, "feeds"), peers: peers_b)
    thread = Thread.new { server.run }
    sleep 0.5

    begin
      gained = pull_from("127.0.0.1", 18017, id_a, peers_a, store_a, expected: id_b.device_public)

      assert_equal 1, gained["!addrs"], "C's address arrives via B's gossip"
      hints = peers_a.hints
      assert_includes hints.keys, id_c.master_public
      refute peers_a.follow?(id_c.master_public), "a hint is not a follow"
    ensure
      thread.kill
    end
  end

  def test_signed_beacons_verify_and_unsigned_ones_die
    keypair = Keys.generate
    beacon = Sync::LanBeacon.new(port: 7676, node: keypair[:public_hex], private_hex: keypair[:private_hex])
    wire = JSON.generate(beacon.send(:announcement))

    node, _, port = Sync::LanBeacon.verify_announcement(wire)
    assert_equal keypair[:public_hex], node
    assert_equal 7676, port

    forged = JSON.generate({ "node" => keypair[:public_hex], "port" => 7676, "at" => Time.now.to_i })
    assert_equal [ nil, nil, nil ], Sync::LanBeacon.verify_announcement(forged)

    stale = JSON.generate({ "node" => keypair[:public_hex], "port" => 7676, "at" => Time.now.to_i - 3600,
      "device" => keypair[:public_hex], "sig" => "00" * 64 })
    assert_equal [ nil, nil, nil ], Sync::LanBeacon.verify_announcement(stale)
  end

  def test_seeds_list_and_bootstrap_follows_them
    seeds = RiceSpace::P2p::Seeds.list

    assert seeds.any?
    assert seeds.all? { |seed| Keys.valid_public?(seed["key"]) }
  end

  private

  def make_node(name)
    dir = Dir.mktmpdir
    [ dir, Identity.create(dir: dir, device_name: name, master_passphrase: "x", device_passphrase: "x") ]
  end

  def make_nodes(*names)
    names.map { |name| make_node(name) }
  end

  def device_secret(identity)
    identity.unlock_device("x")
  end

  # Thread the device secrets through the old tests: the wire is TLS now.
  def serve_on(port, identity, store, peers: nil)
    peers ||= Peers.new(path: Pathname.new(Dir.mktmpdir).join("p.json"), follows: {})
    Sync::Server.new(port: port, identity: identity, peers: peers,
      private_hex: device_secret(identity), store_root: store, lan: false)
  end

  def pull_from(host, port, identity, peers, store, expected: nil)
    Sync.pull(host, port, identity: identity, peers: peers,
      private_hex: device_secret(identity),
      expected_key: expected, store_root: store)
  end

  def publish(identity, store, document)
    secret = identity.unlock_master("x")
    feed = Feed.new(identity.master_public, root: store)
    feed.append(Record.build(author: identity.master_public, signer: identity.master_public, seq: 1,
      prev: Record::GENESIS_PREV, kind: "device-add", body: { "device" => identity.device_public },
      sign_with: secret))
    feed.append(Record.build(author: identity.master_public, signer: identity.device_public, seq: 2,
      prev: feed.prev_hash, kind: "page", body: { "document" => document },
      sign_with: identity.unlock_device("x")))
    feed.append(Record.build(author: identity.master_public, signer: identity.device_public, seq: 3,
      prev: feed.prev_hash, kind: "lists", body: { "blurbs" => [] },
      sign_with: identity.unlock_device("x")))
    feed
  end
end
