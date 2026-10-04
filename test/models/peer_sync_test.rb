# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "ricespace"

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

  private

  def build(author, signer, seq, prev, kind, body)
    RiceSpace::P2p::Record.build(
      author: author[:public_hex], signer: signer[:public_hex],
      seq: seq, prev: prev, kind: kind, body: body, sign_with: signer[:private_hex]
    )
  end
end
