# frozen_string_literal: true

require "ricespace/p2p/canonical"
require "ricespace/p2p/keys"
require "ricespace/p2p/record"
require "ricespace/p2p/feed"

# A replicated feed this node holds: somebody followed, or ourselves. A cache
# of verified records, never an account — nothing here logs in, and no Rating
# or Comment row is ever created for remote content.
class Peer < ApplicationRecord
  HEX = /\A[0-9a-f]{64}\z/

  validates :pubkey, presence: true, uniqueness: true, format: { with: HEX }

  has_many :records, class_name: "PeerRecord", foreign_key: :author_pubkey,
    primary_key: :pubkey, dependent: :delete_all

  scope :followed, -> { where(followed: true) }

  # This node's own feed, bound to the local account.
  def self.own
    find_by(self_feed: true)
  end

  def short_id = RiceSpace::P2p::Canonical.short_id(pubkey)

  # The newest verified page document, or nil.
  def latest_document
    records.where(kind: "page").order(seq: :desc).first&.parsed_body&.dig("document")
  end

  # The newest verified rice facts, or {}.
  def latest_rice
    record = records.where(kind: "rice").order(seq: :desc).first
    record ? record.parsed_body : {}
  end

  # The newest verified lists, or {}.
  def latest_lists
    record = records.where(kind: "lists").order(seq: :desc).first
    record ? record.parsed_body : {}
  end

  # Score from replicated reactions plus local ones: likes minus dislikes over
  # every reaction record aimed at this feed's page or its posts.
  # Last-writer-wins per (author, target): a re-react appends a record, so the
  # tally takes each author's newest opinion per target hash and drops `none`
  # (the withdrawal). Without this a changed mind counts twice.
  def score
    current_reactions.sum { |reaction| reaction["opinion"] == "dislike" ? -1 : 1 }
  end

  def reactions
    current_reactions
  end

  def current_reactions
    latest = {}
    PeerRecord.where(kind: "reaction").order(:id).each do |record|
      body = record.parsed_body
      next unless body["target_feed"] == pubkey
      next unless body["target_hash"].is_a?(String) && !body["target_hash"].empty?

      latest[[ record.author_pubkey, body["target_hash"] ]] = body
    end
    latest.values.reject { |body| body["opinion"] == "none" }
  end

  def comments_on(record_hash)
    PeerRecord.where(kind: "comment").select do |record|
      record.parsed_body["parent_hash"] == record_hash
    end.sort_by(&:seq)
  end
end
