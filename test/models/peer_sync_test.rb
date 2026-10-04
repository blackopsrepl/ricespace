# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "ricespace"
require "ricespace/net/bencode"
require "ricespace/net/endpoint"

class PeerSyncTest < ActiveSupport::TestCase
  include RiceSpace::P2p

  test "verified records import, and a fork marks the peer compromised" do
    master = Keys.generate
    device = Keys.generate
    first = build(master, master, 1, Record::GENESIS_PREV, "device-add", { "device" => device[:public_hex] })
    second = build(master, device, 2, Record.hash_of(first), "page", { "document" => "<marquee>hi</marquee>" })

    result = PeerSync.import_feed(master[:public_hex], [ first, second ])

    assert_equal 2, result[:imported]
    assert_not Peer.find_by(pubkey: master[:public_hex]).compromised?
    assert_equal "<marquee>hi</marquee>", Peer.find_by(pubkey: master[:public_hex]).latest_document

    evil = build(master, device, 2, Record.hash_of(first), "page", { "document" => "evil" })
    result = PeerSync.import_feed(master[:public_hex], [ first, second, evil ])

    assert result[:compromised]
    assert Peer.find_by(pubkey: master[:public_hex]).compromised?
  end

  test "a record with a bad signature is not stored" do
    master = Keys.generate
    evil = Keys.generate
    forged = build(master, evil, 1, Record::GENESIS_PREV, "page", { "document" => "x" })

    result = PeerSync.import_feed(master[:public_hex], [ forged ])

    assert_equal 0, result[:imported]
    assert_equal 0, PeerRecord.where(author_pubkey: master[:public_hex]).count
  end

  test "a score assembles from replicated reactions" do
    owner = Keys.generate
    reactor = Keys.generate
    Peer.create!(pubkey: reactor[:public_hex], followed: true)
    page = build(owner, owner, 1, Record::GENESIS_PREV, "page", { "document" => "x" })
    reaction = build(reactor, reactor, 1, Record::GENESIS_PREV, "reaction",
      { "target_feed" => owner[:public_hex], "target_hash" => Record.hash_of(page), "opinion" => "like" })

    PeerSync.import_feed(owner[:public_hex], [ page ])
    PeerSync.import_feed(reactor[:public_hex], [ reaction ])

    assert_equal 1, Peer.find_by(pubkey: owner[:public_hex]).score
  end

  test "a changed mind counts once, and a withdrawal counts zero" do
    owner = Keys.generate
    reactor = Keys.generate
    Peer.create!(pubkey: reactor[:public_hex], followed: true)
    page = build(owner, owner, 1, Record::GENESIS_PREV, "page", { "document" => "x" })
    target = Record.hash_of(page)
    like = build(reactor, reactor, 1, Record::GENESIS_PREV, "reaction",
      { "target_feed" => owner[:public_hex], "target_hash" => target, "opinion" => "like" })
    change = build(reactor, reactor, 2, Record.hash_of(like), "reaction",
      { "target_feed" => owner[:public_hex], "target_hash" => target, "opinion" => "dislike" })

    PeerSync.import_feed(owner[:public_hex], [ page ])
    PeerSync.import_feed(reactor[:public_hex], [ like, change ])

    assert_equal(-1, Peer.find_by(pubkey: owner[:public_hex]).score)

    away = build(reactor, reactor, 3, Record.hash_of(change), "reaction",
      { "target_feed" => owner[:public_hex], "target_hash" => target, "opinion" => "none" })
    PeerSync.import_feed(reactor[:public_hex], [ like, change, away ])

    assert_equal 0, Peer.find_by(pubkey: owner[:public_hex]).score
  end

  test "a loose node secret refuses to sign" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "node_secret")
      File.write(file, "0" * 64)
      File.chmod(0o644, file)
      ENV["RICESPACE_NODE_SECRET_FILE"] = file

      assert_nil PeerWrite.node_device_public
      assert_not PeerWrite.authorized?(User.create!(username: "loose", email_address: "loose@example.com",
        password: "correct horse battery"))
    ensure
      ENV.delete("RICESPACE_NODE_SECRET_FILE")
    end
  end

  test "store refresh only imports explicitly followed feeds and never creates follows" do
    Dir.mktmpdir do |dir|
      trusted = Keys.generate
      stranger = Keys.generate
      Peer.create!(pubkey: trusted[:public_hex], followed: true)
      [ trusted, stranger ].each do |key|
        Feed.new(key[:public_hex], root: dir).append(
          build(key, key, 1, Record::GENESIS_PREV, "page", { "document" => "disk page" }))
      end
      result = PeerSync.import_store(dir)
      assert_equal 1, result[:imported]
      assert_nil Peer.find_by(pubkey: stranger[:public_hex])
      assert_equal 0, PeerSync.import_store(dir)[:imported]
      assert_equal 1, PeerRecord.where(author_pubkey: trusted[:public_hex]).count
    end
  end

  test "a network-replicated feed imports after relay-assisted sync" do
    # The records arrived over a bridged connection (see
    # cli/test/net_relay_test.rb for the wire); Rails only sees verified
    # records on disk and imports the followed feed.
    owner = Keys.generate
    device = Keys.generate
    Dir.mktmpdir do |dir|
      feed = Feed.new(owner[:public_hex], root: dir)
      feed.append(build(owner, owner, 1, Record::GENESIS_PREV,
        "device-add", { "device" => device[:public_hex] }))
      feed.append(build(owner, device, 2, Record.hash_of(feed.records.first),
        "page", { "document" => "bridged page" }))
      Peer.create!(pubkey: owner[:public_hex], followed: true)

      result = PeerSync.import_store(dir)

      assert_equal 2, result[:imported]
      assert_equal "bridged page", Peer.find_by(pubkey: owner[:public_hex]).latest_document
    end
  end

  test "endpoint signatures never create records and never become follows" do
    master = Keys.generate
    device = Keys.generate
    slot = RiceSpace::P2p::Net::Endpoint.build(node: master[:public_hex], device: device[:public_hex],
      addrs: [ "203.0.113.7:7676" ], sign_with: device[:private_hex])

    assert_not PeerRecord::KINDS.include?("endpoint")
    assert_nil Peer.find_by(pubkey: master[:public_hex])
    assert slot["sig"].match?(/\A[0-9a-f]{128}\z/)
  end

  test "a foreign author cannot be imported under another feed key" do
    owner = Keys.generate
    stranger = Keys.generate
    Peer.create!(pubkey: owner[:public_hex])
    record = build(stranger, stranger, 1, Record::GENESIS_PREV, "page", { "document" => "wrong author" })
    assert_equal 0, PeerSync.import_feed(owner[:public_hex], [ record ])[:imported]
    assert_nil Peer.find_by(pubkey: owner[:public_hex]).latest_document
  end

  private

  def build(author, signer, seq, prev, kind, body)
    RiceSpace::P2p::Record.build(
      author: author[:public_hex], signer: signer[:public_hex],
      seq: seq, prev: prev, kind: kind, body: body, sign_with: signer[:private_hex]
    )
  end
end
