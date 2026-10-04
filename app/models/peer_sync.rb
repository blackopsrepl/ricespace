# frozen_string_literal: true

# Verified records from a feed directory into the database. Every record is
# chain-verified before it touches a row: an unverified record is not stored,
# and a fork marks the peer compromised rather than picking a side.
module PeerSync
  # Import a whole store directory (the node's feed root). Returns
  # { imported:, compromised: [] }.
  def self.import_store(store_root)
    imported = 0
    compromised = []
    root = Pathname.new(store_root.to_s)
    return { imported: 0, compromised: [] } unless root.directory?

    root.children.select(&:directory?).each do |dir|
      result = import_feed(dir.basename.to_s, records_from(dir))
      imported += result[:imported]
      compromised << dir.basename.to_s if result[:compromised]
    end
    { imported: imported, compromised: compromised }
  end

  def self.records_from(dir)
    Pathname.new(dir.to_s).children
      .select { |child| child.file? && child.extname == ".json" }
      .sort.filter_map do |file|
        JSON.parse(file.read)
      rescue JSON::ParserError
        nil
      end
  end

  # Verify, then store. Skips records already held; refuses the whole batch's
  # tail past the first failure (a chain with a hole is not imported past it).
  def self.import_feed(pubkey, records)
    peer = Peer.find_or_initialize_by(pubkey: pubkey)
    if peer.new_record?
      peer.followed = true
      peer.save!
    end

    # Dedup by hash, not by seq: a fork carries a known seq with an unknown
    # hash, and skipping it as "already have" would miss the compromise.
    have_hashes = peer.records.pluck(:record_hash).compact.to_set
    fresh = records.reject { |record| have_hashes.include?(RiceSpace::P2p::Record.hash_of(record)) }
      .sort_by { |record| record["seq"].to_i }
    return { imported: 0, compromised: peer.compromised? } if fresh.empty?

    chain = peer.records.order(:seq).map(&:to_p2p) + fresh
    result = RiceSpace::P2p::Record.verify_chain(chain)

    if result.forks.any?
      peer.compromised = true
      peer.save!
      return { imported: 0, compromised: true }
    end

    imported = 0
    ApplicationRecord.transaction do
      fresh.each do |record|
        break unless result_reaches?(result, record["seq"])

        peer.records.create!(
          seq: record["seq"], kind: record["kind"],
          body_json: RiceSpace::P2p::Canonical.json(record["body"]),
          signer: record["signer"], signature: record["sig"],
          record_hash: RiceSpace::P2p::Record.hash_of(record),
          prev_hash: record["prev"]
        )
        imported += 1
      end
      peer.latest_seq = peer.records.maximum(:seq) || 0
      peer.latest_hash = peer.records.order(seq: :desc).first&.record_hash
      peer.deleted = result.state["deleted"]
      peer.save!
    end
    { imported: imported, compromised: false }
  end

  # The verified walk reached this seq (no error at or before it).
  def self.result_reaches?(result, seq)
    bad = result.errors.filter_map do |message|
      message[/\Aseq (\d+)/, 1]&.to_i
    end.min
    bad.nil? || seq.to_i < bad
  end
end
