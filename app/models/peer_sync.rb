# frozen_string_literal: true

# SQLite is an index of verified feeds, not the transport's trust policy.
module PeerSync
  def self.import_store(store_root)
    totals = { imported: 0, compromised: [], errors: [] }
    root = Pathname.new(store_root.to_s)
    return totals unless root.directory?

    # Never discover follows from directories: transport quarantine and disk
    # possession are not permission to display a feed.
    Peer.followed.find_each do |peer|
      dir = root.join(peer.pubkey)
      next unless dir.directory?

      begin
        result = import_feed(peer.pubkey, records_from(dir))
        totals[:imported] += result[:imported]
        totals[:compromised] << peer.pubkey if result[:compromised]
        totals[:errors].concat(Array(result[:errors]))
      rescue RiceSpace::P2p::Error, JSON::ParserError, SystemCallError, ActiveRecord::ActiveRecordError => error
        totals[:errors] << "#{peer.short_id}: #{error.class}"
        Rails.logger.warn("Feed refresh failed for #{peer.short_id}: #{error.class}")
      end
    end
    totals
  end

  def self.records_from(dir)
    Pathname.new(dir.to_s).children
      .select { |child| child.file? && child.extname == ".json" }
      .sort.map { |file| RiceSpace::P2p::Record.from_hash(JSON.parse(file.read)) }
  end

  def self.import_feed(pubkey, records)
    records = records.map { |record| RiceSpace::P2p::Record.from_hash(record) }
    unless records.all? { |record| record["author"] == pubkey }
      return { imported: 0, compromised: false, errors: [ "feed author mismatch" ] }
    end

    ApplicationRecord.transaction do
      peer = Peer.find_or_create_by!(pubkey: pubkey) { |entry| entry.followed = false }
      peer.lock!
      have_hashes = peer.records.pluck(:record_hash).compact.to_set
      fresh = records.reject { |record| have_hashes.include?(RiceSpace::P2p::Record.hash_of(record)) }
        .sort_by { |record| record["seq"] }
      next { imported: 0, compromised: peer.compromised?, errors: [] } if fresh.empty?

      chain = peer.records.order(:seq).map(&:to_p2p) + fresh
      result = RiceSpace::P2p::Record.verify_chain(chain)
      if result.forks.any?
        peer.update!(compromised: true)
        next { imported: 0, compromised: true, errors: result.errors }
      end

      imported = 0
      fresh.each do |record|
        break unless result_reaches?(result, record["seq"])

        peer.records.create!(
          seq: record["seq"], kind: record["kind"],
          body_json: RiceSpace::P2p::Canonical.json(record["body"]),
          signer: record["signer"], signature: record["sig"],
          record_hash: RiceSpace::P2p::Record.hash_of(record), prev_hash: record["prev"]
        )
        imported += 1
      end
      stored = RiceSpace::P2p::Record.verify_chain(peer.records.order(:seq).map(&:to_p2p))
      peer.update!(latest_seq: stored.state["seq"], latest_hash: stored.state["head"],
        deleted: stored.state["deleted"])
      { imported: imported, compromised: peer.compromised?, errors: result.errors }
    end
  end

  def self.result_reaches?(result, seq)
    bad = result.errors.filter_map { |message| message[/\Aseq (\d+)/, 1]&.to_i }.min
    bad.nil? || seq < bad
  end
end
