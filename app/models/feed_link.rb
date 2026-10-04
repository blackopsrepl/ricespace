# frozen_string_literal: true

# Account possession proof is separate from device authorization. The session
# owns the challenge; signing arbitrary public keys is not account possession.
module FeedLink
  def self.challenge(user, origin)
    "ricespace-link-v1:#{origin}:#{user.id}:#{PeerWrite.node_device_public}:#{SecureRandom.hex(32)}"
  end

  def self.link!(user, key, proof, challenge)
    feed = RiceSpace::P2p::Feed.new(key)
    result = feed.verify
    unless result.ok? && result.state["author"] == key && !result.state["deleted"] &&
        RiceSpace::P2p::Keys.verify(result.state["owner"], proof, challenge)
      raise RiceSpace::P2p::Error, "Ownership proof failed — sign this studio's fresh challenge with the current master."
    end
    unless PeerWrite.device_authorized?(result)
      raise RiceSpace::P2p::Error, "Authorise this node device in the feed before linking."
    end
    ApplicationRecord.transaction do
      user.lock!
      if user.pubkey.present? && user.pubkey != key
        raise RiceSpace::P2p::Error, "Unlink your existing feed before linking another."
      end
      user.update!(pubkey: key, feed_link_verified: true)
      peer, = PeerWrite.own_feed(user)
      raise RiceSpace::P2p::Error, "This feed is compromised." if peer.compromised?

      PeerSync.import_feed(key, feed.records)
      FeedHydration.refresh(user)
    end
  end

  def self.unlink!(user)
    ApplicationRecord.transaction do
      Peer.find_by(pubkey: user.pubkey)&.update!(self_feed: false)
      user.update!(pubkey: nil, feed_link_verified: false, feed_snapshot: {}, feed_sync_status: nil)
    end
  end
end
