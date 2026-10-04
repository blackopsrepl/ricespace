# frozen_string_literal: true

class CreatePeers < ActiveRecord::Migration[8.1]
  def change
    # A replicated feed this node holds: somebody we follow (or ourselves),
    # cached from sync rather than owned like a User. Never logs in.
    create_table :peers do |t|
      t.string :pubkey, null: false
      t.string :petname
      t.boolean :followed, default: true, null: false
      t.boolean :self_feed, default: false, null: false
      t.integer :latest_seq, default: 0, null: false
      t.string :latest_hash
      t.boolean :compromised, default: false, null: false
      t.boolean :deleted, default: false, null: false
      t.timestamps
    end
    add_index :peers, :pubkey, unique: true

    # The raw replicated truth: every verified record of every held feed.
    # Local Rating/Comment rows are never created for remote content — this
    # table is what the node renders from.
    create_table :peer_records do |t|
      t.string :author_pubkey, null: false
      t.integer :seq, null: false
      t.string :kind, null: false
      t.text :body_json, null: false, default: "{}"
      t.string :signer
      t.string :signature
      t.string :record_hash
      t.string :prev_hash
      t.timestamps
    end
    add_index :peer_records, [ :author_pubkey, :seq ], unique: true
    add_index :peer_records, [ :author_pubkey, :kind ]
  end
end
