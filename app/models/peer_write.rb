# frozen_string_literal: true

# Signing local intent into the node's own feeds. The browser writes a Rating
# row for local pages; for replicated ones it signs a record instead — the
# sync carries it to the page's owner, whose node verifies it like any other.
#
# The server signs with its node-device key, which the account owner authorises
# once with a `device-add` record (signed by their master, e.g. from the CLI):
# the node is one of the account's devices, not the account. Without that
# authorisation, remote reactions are refused rather than forged.
module PeerWrite
  def self.own_feed(user)
    raise RiceSpace::P2p::Error, "link this account to a feed first" if user.pubkey.blank?

    peer = Peer.find_or_initialize_by(pubkey: user.pubkey)
    peer.self_feed = true
    peer.followed = true
    peer.save!
    [ peer, RiceSpace::P2p::Feed.new(user.pubkey) ]
  end

  # Whether this node may sign for the account: the node-device is a live,
  # unrevoked device on the feed.
  def self.authorized?(user)
    return false unless user.feed_link_verified? && user.pubkey.present? && node_device_public.present?

    result = RiceSpace::P2p::Feed.new(user.pubkey).verify
    device_authorized?(result)
  rescue RiceSpace::P2p::Error, SystemCallError
    false
  end

  def self.device_authorized?(result)
    return false unless result.ok? && !result.state["deleted"] && node_device_public.present?

    device = result.state["devices"][node_device_public]
    return false if device.nil? || !device["added"]
    return false if device["revoked"]

    cutoff = result.state["revocations"][node_device_public]
    cutoff.nil?
  rescue RiceSpace::P2p::Error
    false
  end

  # Publish the owner's current page into their feed after a local write.
  # Opportunistic: when the account is linked and this node may sign, the
  # page/rice/lists go in as records; otherwise nothing happens. The CLI's
  # `folder sign --all` is the authoritative publish — this keeps the local
  # replica warm between pushes.
  def self.publish_local(user)
    return unless authorized?(user)

    _own, feed = own_feed(user)
    profile = user.profile
    bodies = [
      [ "page", { "document" => profile.document.to_s } ],
      [ "rice", rice_body_for(user) ],
      [ "lists", lists_body_for(user) ]
    ]
    ApplicationRecord.transaction do
      bodies.each do |kind, body|
        record = RiceSpace::P2p::Record.build(
          author: user.pubkey, signer: node_device_public,
          seq: feed.next_seq, prev: feed.prev_hash,
          kind: kind, body: body, sign_with: node_device_secret
        )
        feed.append(record)
      end
      PeerSync.import_feed(user.pubkey, feed.records)
      FeedHydration.acknowledge(user)
    end
    true
  rescue RiceSpace::P2p::Error
    false
  end

  def self.rice_body_for(user)
    showcase = user.showcase
    return {} if showcase.nil?

    {
      "title" => showcase.title.to_s, "summary" => showcase.summary.to_s,
      "details" => showcase.details.to_s,
      "facts" => showcase.facts.to_h,
      "shots" => []
    }
  end

  def self.lists_body_for(user)
    {
      "blurbs" => user.blurbs.in_order.map { |blurb| { "title" => blurb.title, "body" => blurb.body } },
      "demos" => user.demos.in_order.map do |demo|
        { "title" => demo.title, "group" => demo.group_name, "party" => demo.party,
          "year" => demo.release_year, "platform" => demo.platform, "category" => demo.category,
          "placing" => demo.ranking, "url" => demo.url, "note" => demo.watch_note }
      end,
      "builds" => user.builds.in_order.map do |build|
        { "title" => build.title, "kind" => build.kind, "summary" => build.summary,
          "specs" => build.specs, "cooling" => build.cooling, "details" => build.details }
      end,
      "links" => user.stream_links.order(:created_at).map do |link|
        { "platform" => link.platform, "url" => link.url, "title" => link.title }
      end,
      "friends" => user.friendships.in_order.filter_map do |friendship|
        next unless friendship.friend.pubkey.present?

        { "peer" => friendship.friend.pubkey, "petname" => friendship.friend.username }
      end
    }
  end

  # Close the account's feed on the network. Best-effort by design: without
  # an authorized node-device there is nothing to sign with, and the local
  # rows go regardless. Returns true when the tombstone landed.
  def self.goodbye(user, message: nil)
    return false unless authorized?(user)

    _own, feed = own_feed(user)
    body = {}
    body["message"] = message.to_s[0, 140] if message
    record = RiceSpace::P2p::Record.build(
      author: user.pubkey, signer: node_device_public,
      seq: feed.next_seq, prev: feed.prev_hash,
      kind: "tombstone", body: body, sign_with: node_device_secret
    )
    feed.append(record)
    PeerSync.import_feed(user.pubkey, feed.records)
    true
  rescue RiceSpace::P2p::Error
    false
  end

  # A reaction to a replicated page, signed into the signer's own feed.
  def self.react(user:, peer:, opinion:, target_hash:)
    _own, feed = own_feed(user)
    record = RiceSpace::P2p::Record.build(
      author: user.pubkey, signer: node_device_public,
      seq: feed.next_seq, prev: feed.prev_hash,
      kind: "reaction",
      body: { "target_feed" => peer.pubkey, "target_hash" => target_hash, "opinion" => opinion },
      sign_with: node_device_secret
    )
    feed.append(record)
    PeerSync.import_feed(user.pubkey, feed.records)
    record
  end

  # A comment on a replicated post, signed into the signer's own feed.
  def self.comment(user:, parent_hash:, text:)
    _own, feed = own_feed(user)
    record = RiceSpace::P2p::Record.build(
      author: user.pubkey, signer: node_device_public,
      seq: feed.next_seq, prev: feed.prev_hash,
      kind: "comment",
      body: { "parent_hash" => parent_hash, "text" => text },
      sign_with: node_device_secret
    )
    feed.append(record)
    PeerSync.import_feed(user.pubkey, feed.records)
    record
  end

  # This node's device keypair. Generated once per node, kept outside the repo
  # (RICESPACE_NODE_SECRET_FILE); the public half is what the account owner
  # authorises with `device-add`.
  def self.node_device_public
    secret = node_device_secret(raise_error: false)
    return nil if secret.nil?

    RiceSpace::P2p::Keys.public_from_private(secret)
  end

  def self.node_device_secret(raise_error: true)
    file = ENV["RICESPACE_NODE_SECRET_FILE"].to_s
    if file.empty? || !File.file?(file)
      raise RiceSpace::P2p::Error, "this node has no device key" if raise_error

      return nil
    end
    # A secret readable by anyone on the machine signs for every account that
    # authorised this node. Refuse it rather than read it.
    mode = File.stat(file).mode & 0o777
    if mode & 0o077 != 0
      raise RiceSpace::P2p::Error, "the node secret at #{file} is readable by others (mode %o) — chmod 600 it" % mode if raise_error

      return nil
    end
    File.read(file).strip
  end
end
