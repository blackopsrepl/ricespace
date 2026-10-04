# frozen_string_literal: true

require "test_helper"
require "ricespace"
require "tmpdir"

class FeedLinkingTest < ActionDispatch::IntegrationTest
  include RiceSpace::P2p

  setup do
    @dir = Dir.mktmpdir
    @old_store = ENV["RICESPACE_STORE"]
    @old_secret = ENV["RICESPACE_NODE_SECRET_FILE"]
    ENV["RICESPACE_STORE"] = File.join(@dir, "feeds")
    ENV["RICESPACE_NODE_SECRET_FILE"] = File.join(@dir, "node")
    @master = Keys.generate
    @node = Keys.generate
    File.write(ENV["RICESPACE_NODE_SECRET_FILE"], @node[:private_hex], perm: 0o600)
    @user = User.create!(username: "linker", email_address: "linker@example.com", password: "correct horse battery")
    @feed = Feed.new(@master[:public_hex])
    append("device-add", { "device" => @node[:public_hex] })
    append("page", { "document" => "<h1>From disk</h1>" })
    sign_in_as @user
  end

  teardown do
    ENV["RICESPACE_STORE"] = @old_store
    ENV["RICESPACE_NODE_SECRET_FILE"] = @old_secret
    FileUtils.remove_entry(@dir)
  end

  test "public key alone is not ownership proof" do
    patch link_feed_account_path, params: { user: { pubkey: @master[:public_hex] } }
    assert_redirected_to studio_path
    assert_nil @user.reload.pubkey
    assert_nil Peer.find_by(pubkey: @master[:public_hex])
    assert_equal "", @user.profile.reload.document
  end

  test "proven pairing hydrates studio and the next request imports disk updates automatically" do
    link
    assert_equal @master[:public_hex], @user.reload.pubkey
    assert Peer.find_by!(pubkey: @master[:public_hex]).self_feed?
    assert_equal "<h1>From disk</h1>", @user.profile.reload.document
    append("page", { "document" => "<h1>Synced later</h1>" })
    get studio_path
    assert_response :success
    assert_equal "<h1>Synced later</h1>", @user.profile.reload.document
    assert_equal 3, PeerRecord.where(author_pubkey: @master[:public_hex]).count
    assert_select "textarea", text: "<h1>Synced later</h1>"
    get peer_path(@master[:public_hex])
    assert_response :success
    assert_select "h1", text: "Synced later"
  end

  test "a local unsynced edit is retained and reported instead of overwritten" do
    link
    @user.profile.update!(document: "local draft")
    append("page", { "document" => "remote edit" })
    get studio_path
    assert_equal "local draft", @user.profile.reload.document
    assert_equal "remote edit", Peer.find_by!(pubkey: @master[:public_hex]).latest_document
    assert_includes response.body, "Local edits preserved"
  end

  test "revocation stops hydration even though verified replica records advance" do
    link
    append("device-revoke", { "device" => @node[:public_hex], "cutoff_seq" => @feed.next_seq })
    append("page", { "document" => "after revoke" })
    get studio_path
    assert_equal "<h1>From disk</h1>", @user.profile.reload.document
    assert_equal "after revoke", Peer.find_by!(pubkey: @master[:public_hex]).latest_document
  end

  test "a signature from another master cannot link" do
    get studio_path
    challenge = css_select("[data-feed-challenge]").first["data-feed-challenge"]
    patch link_feed_account_path, params: { user: { pubkey: @master[:public_hex], proof: Keys.sign(Keys.generate[:private_hex], challenge) } }
    assert_nil @user.reload.pubkey
  end

  test "unlink clears ownership and does not hydrate later records" do
    link
    patch link_feed_account_path, params: { user: { pubkey: "" } }
    assert_nil @user.reload.pubkey
    assert_not Peer.find_by!(pubkey: @master[:public_hex]).self_feed?
    append("page", { "document" => "unlinked" })
    get studio_path
    assert_equal "<h1>From disk</h1>", @user.profile.reload.document
  end

  test "unfollowed disk content cannot become a visible peer" do
    get peers_path
    assert_response :success
    assert_nil Peer.find_by(pubkey: @master[:public_hex])
    Peer.create!(pubkey: @master[:public_hex], followed: false)
    PeerSync.import_feed(@master[:public_hex], @feed.records)
    get peer_path(@master[:public_hex])
    assert_response :not_found
    assert_equal 2, PeerRecord.where(author_pubkey: @master[:public_hex]).count
  end

  test "a tombstone hides the replicated page and retains local editor content" do
    link
    append("tombstone", {})
    get peer_path(@master[:public_hex])
    assert_response :gone
    assert_not_includes response.body, "From disk"
    get studio_path
    assert_equal "<h1>From disk</h1>", @user.profile.reload.document
  end

  test "pairing without node authorization is refused even with master proof" do
    append("device-revoke", { "device" => @node[:public_hex], "cutoff_seq" => @feed.next_seq })
    link
    assert_nil @user.reload.pubkey
    assert_nil Peer.find_by(pubkey: @master[:public_hex])
  end

  test "rice and textual lists hydrate with the page" do
    append("rice", { "title" => "Signed rice", "details" => "facts", "facts" => { "window manager" => "Sway" } })
    append("lists", { "blurbs" => [ { "title" => "Music", "body" => "Signed music" } ],
      "demos" => [ { "title" => "Demo", "platform" => "Linux" } ],
      "builds" => [ { "title" => "Rig", "kind" => "desktop", "details" => "Built it" } ],
      "links" => [ { "url" => "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "title" => "Clip" } ] })
    link
    assert_equal "Signed rice", @user.reload.showcase.title
    assert_equal "Sway", @user.showcase.window_manager
    assert_equal "Signed music", @user.blurbs.first.body
    assert_equal "Demo", @user.demos.first.title
    assert_equal "Rig", @user.builds.first.title
    assert_equal "Clip", @user.stream_links.first.title
  end

  test "invalid editor metadata rolls back page and lists without losing the replica" do
    append("lists", { "blurbs" => [ { "title" => "x" * 100, "body" => "bad title" } ] })
    link
    assert_equal @master[:public_hex], @user.reload.pubkey
    assert_equal "", @user.profile.reload.document
    assert_empty @user.blurbs
    assert_includes @user.feed_sync_status, "refresh refused"
    assert_equal "<h1>From disk</h1>", Peer.find_by!(pubkey: @master[:public_hex]).latest_document
  end

  test "damaged disk files are isolated and a corrected feed is retried" do
    link
    other = Keys.generate
    Peer.create!(pubkey: other[:public_hex], followed: true)
    dir = Feed.new(other[:public_hex]).dir
    dir.mkpath
    dir.join("00000001.json").write("broken")
    append("page", { "document" => "healthy feed advances" })
    get studio_path
    assert_response :success
    assert_equal "healthy feed advances", @user.profile.reload.document
    dir.join("00000001.json").delete
    Feed.new(other[:public_hex]).append(Record.build(author: other[:public_hex], signer: other[:public_hex],
      seq: 1, prev: Record::GENESIS_PREV, kind: "page", body: { "document" => "retried" }, sign_with: other[:private_hex]))
    get peer_path(other[:public_hex])
    assert_response :success
    assert_equal "retried", Peer.find_by!(pubkey: other[:public_hex]).latest_document
  end

  test "legacy key-only links cannot authorize writes or hydrate" do
    @user.update!(pubkey: @master[:public_hex])
    PeerWrite.own_feed(@user)
    get studio_path
    assert_equal "", @user.profile.reload.document
    assert_not PeerWrite.authorized?(@user.reload)
  end

  test "expired proof cannot link" do
    get studio_path
    challenge = css_select("[data-feed-challenge]").first["data-feed-challenge"]
    travel 11.minutes do
      patch link_feed_account_path, params: { user: { pubkey: @master[:public_hex], proof: Keys.sign(@master[:private_hex], challenge) } }
    end
    assert_nil @user.reload.pubkey
  end

  test "proof cannot be replayed after unlink" do
    get studio_path
    challenge = css_select("[data-feed-challenge]").first["data-feed-challenge"]
    proof = Keys.sign(@master[:private_hex], challenge)
    attributes = { user: { pubkey: @master[:public_hex], proof: proof } }
    patch link_feed_account_path, params: attributes
    patch link_feed_account_path, params: { user: { pubkey: "" } }
    patch link_feed_account_path, params: attributes
    assert_nil @user.reload.pubkey
  end

  test "successful signed browser publish becomes the merge base for later remote changes" do
    link
    patch studio_path, params: { profile: { document: "published draft", version: @user.profile.reload.version } }
    assert_redirected_to studio_path
    assert_equal "published draft", @feed.records.last["body"]["document"] if @feed.records.last["kind"] == "page"
    append("page", { "document" => "next remote" })
    get studio_path
    assert_equal "next remote", @user.profile.reload.document
    assert_nil @user.reload.feed_sync_status
  end

  test "live TLS replication becomes visible on the next browser request without manual import" do
    remote = Identity.create(dir: File.join(@dir, "remote-config"), device_name: "remote",
      master_passphrase: "test-only", device_passphrase: "test-only")
    remote_root = File.join(@dir, "remote-feeds")
    remote_feed = Feed.new(remote.master_public, root: remote_root)
    remote_feed.append(Record.build(author: remote.master_public, signer: remote.master_public,
      seq: 1, prev: Record::GENESIS_PREV, kind: "device-add", body: { "device" => remote.device_public },
      sign_with: remote.unlock_master("test-only")))
    remote_feed.append(Record.build(author: remote.master_public, signer: remote.device_public,
      seq: 2, prev: remote_feed.prev_hash, kind: "page", body: { "document" => "<h1>Arrived over TLS</h1>" },
      sign_with: remote.unlock_device("test-only")))
    receiver = Identity.create(dir: File.join(@dir, "receiver-config"), device_name: "receiver",
      master_passphrase: "test-only", device_passphrase: "test-only")
    peers = Peers.new(path: Pathname.new(@dir).join("receiver-peers.json"), follows: {})
    peers.add(remote.master_public, petname: "remote")
    serving_peers = Peers.new(path: Pathname.new(@dir).join("remote-peers.json"), follows: {})
    reservation = TCPServer.new("127.0.0.1", 0)
    port = reservation.addr[1]
    reservation.close
    server = Sync::Server.new(port: port, identity: remote, peers: serving_peers,
      private_hex: remote.unlock_device("test-only"), store_root: remote_root, lan: false)
    thread = Thread.new { server.run }
    Timeout.timeout(3) do
      loop do
        begin
          TCPSocket.new("127.0.0.1", port).close
          break
        rescue Errno::ECONNREFUSED
          sleep 0.01
        end
      end
    end
    Peer.create!(pubkey: remote.master_public, followed: true)
    gained = Sync.pull("127.0.0.1", port, identity: receiver, peers: peers,
      private_hex: receiver.unlock_device("test-only"), expected_key: remote.device_public,
      store_root: ENV.fetch("RICESPACE_STORE"), publish: false)
    assert_equal 2, gained[remote.master_public]
    assert_equal 0, PeerRecord.where(author_pubkey: remote.master_public).count
    get peer_path(remote.master_public)
    assert_response :success
    assert_select "h1", text: "Arrived over TLS"
    assert_equal 2, PeerRecord.where(author_pubkey: remote.master_public).count
  ensure
    thread&.kill
    thread&.join
  end

  private
    def append(kind, body)
      @feed.append(Record.build(author: @master[:public_hex], signer: @master[:public_hex], seq: @feed.next_seq,
        prev: @feed.prev_hash, kind: kind, body: body, sign_with: @master[:private_hex]))
    end

    def link
      get studio_path
      challenge = css_select("[data-feed-challenge]").first["data-feed-challenge"]
      patch link_feed_account_path, params: { user: { pubkey: @master[:public_hex], proof: Keys.sign(@master[:private_hex], challenge) } }
      assert_redirected_to studio_path
    end

    def sign_in_as(user)
      ApplicationController::RATE_LIMIT_STORE.clear
      post session_path, params: { email_address: user.email_address, password: "correct horse battery" }
    end
end
