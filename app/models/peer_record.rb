# frozen_string_literal: true

# One verified record of a replicated feed. Raw replicated truth: the node
# renders remote pages from these rows, never from local Rating/Comment rows
# (which are only ever about local accounts).
require "ricespace/p2p/record"

class PeerRecord < ApplicationRecord
  KINDS = RiceSpace::P2p::Record::KINDS

  validates :author_pubkey, presence: true
  validates :seq, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :seq, uniqueness: { scope: :author_pubkey }

  belongs_to :peer, class_name: "Peer", foreign_key: :author_pubkey,
    primary_key: :pubkey, optional: true

  def parsed_body
    JSON.parse(body_json || "{}")
  rescue JSON::ParserError
    {}
  end

  def to_p2p
    {
      "author" => author_pubkey, "signer" => signer, "seq" => seq,
      "prev" => self[:prev_hash].presence || RiceSpace::P2p::Record::GENESIS_PREV,
      "kind" => kind, "body" => parsed_body, "sig" => signature
    }
  end
end
