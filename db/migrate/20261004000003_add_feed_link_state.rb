# frozen_string_literal: true

class AddFeedLinkState < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :feed_link_verified, :boolean, default: false, null: false
    add_column :users, :feed_snapshot, :json, default: {}, null: false
    add_column :users, :feed_sync_status, :string
    change_column_default :peers, :followed, from: true, to: false
  end
end
