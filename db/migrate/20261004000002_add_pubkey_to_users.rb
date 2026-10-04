# frozen_string_literal: true

class AddPubkeyToUsers < ActiveRecord::Migration[8.1]
  def change
    # The local account's binding to its P2P feed. Null until the owner links
    # one; unique when present.
    add_column :users, :pubkey, :string
    add_index :users, :pubkey, unique: true
  end
end
