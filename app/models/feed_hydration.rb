# frozen_string_literal: true

# Signed textual state -> editable local state. The previous local snapshot is
# the merge base, not a timestamp: a failed publish must not erase a draft.
module FeedHydration
  LIST_FIELDS = {
    "blurbs" => { "title" => "title", "body" => "body" },
    "demos" => { "title" => "title", "group" => "group_name", "party" => "party", "year" => "release_year",
      "platform" => "platform", "category" => "category", "placing" => "ranking", "url" => "url", "note" => "watch_note" },
    "builds" => { "title" => "title", "kind" => "kind", "summary" => "summary", "specs" => "specs",
      "cooling" => "cooling", "details" => "details" },
    "links" => { "url" => "url", "title" => "title" }
  }.freeze

  def self.snapshot(user)
    lists = PeerWrite.lists_body_for(user).except("friends")
    { "page" => user.profile.document.to_s, "rice" => PeerWrite.rice_body_for(user), "lists" => lists }
  end

  def self.refresh(user)
    return unless user.feed_link_verified? && user.pubkey.present?

    user.with_lock(requires_new: true) do
      peer = Peer.find_by(pubkey: user.pubkey)
      if peer.nil? || !peer.followed? || peer.compromised? || peer.deleted? || !PeerWrite.authorized?(user)
        user.update!(feed_sync_status: "Feed unavailable or node authorization revoked; local state retained.")
        next
      end
      user.reload
      local = snapshot(user)
      baseline = user.feed_snapshot
      if baseline.empty? ? !pristine?(user) : local != baseline
        user.update!(feed_sync_status: "Local edits preserved — publish your draft or reconcile it with the replicated feed.")
        next
      end
      document = peer.latest_document
      user.profile.update!(document: document) unless document.nil? || document == user.profile.document
      hydrate_rice(user, peer.latest_rice) if peer.records.where(kind: "rice").exists?
      hydrate_lists(user, peer.latest_lists) if peer.records.where(kind: "lists").exists?
      user.reload.update!(feed_snapshot: snapshot(user), feed_sync_status: nil)
    end
  rescue RiceSpace::P2p::Error, ActiveRecord::ActiveRecordError, ArgumentError, TypeError => error
    # The transaction rolls back all editor changes. Replica import is separate
    # and remains useful even when editor constraints are stricter than protocol.
    user.reload.update!(feed_sync_status: "Feed editor refresh refused (#{error.class}); local state retained.")
  end

  def self.pristine?(user)
    user.profile.document.blank? && user.showcase.nil? &&
      user.blurbs.empty? && user.demos.empty? && user.builds.empty? && user.stream_links.empty?
  end

  def self.hydrate_rice(user, body)
    rice = user.showcase || user.build_showcase
    facts = body.fetch("facts", {})
    raise RiceSpace::P2p::Error, "rice facts must be a map" unless facts.is_a?(Hash)

    attrs = body.slice("title", "summary", "details")
    Showcase::FACTS.each { |field, label| attrs[field] = facts[label].to_s }
    rice.update!(attrs)
  end

  def self.hydrate_lists(user, body)
    LIST_FIELDS.each do |kind, fields|
      next unless body.key?(kind)

      association = kind == "links" ? user.stream_links.order(:created_at) : user.public_send(kind).in_order
      rows = association.to_a
      entries = body[kind]
      # A deletion must not destroy local-only attachments or conversation.
      rows.drop(entries.length).each do |row|
        if row.comments.exists? || row.reactions.exists? || (row.respond_to?(:photos) && row.photos.exists?)
          raise RiceSpace::P2p::Error, "local media or conversation prevents list deletion"
        end
        row.destroy!
      end
      entries.each_with_index do |entry, index|
        raise RiceSpace::P2p::Error, "list entries must be maps" unless entry.is_a?(Hash)

        attrs = fields.to_h { |wire, column| [ column, entry[wire] ] }
        row = rows[index] || user.public_send(kind == "links" ? :stream_links : kind).build
        row.update!(attrs)
      end
    end
  end

  def self.acknowledge(user)
    user.reload.update!(feed_snapshot: snapshot(user), feed_sync_status: nil) if user.feed_link_verified?
  end
end
