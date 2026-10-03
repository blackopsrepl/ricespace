class AddSongAndFriendOrder < ActiveRecord::Migration[8.1]
  def change
    # The profile song: the one track that plays when somebody opens the page. Two
    # columns on the page itself, because a page has one song and it is part of the
    # page — not a playlist, not a library.
    change_table :profiles, bulk: true do |t|
      t.string :song_url
      t.string :song_title
    end

    # Friends are ordered by their owner, not sorted: the first eight are the ones
    # the page shows first, and the order is the owner's.
    add_column :friendships, :position, :integer, null: false, default: 0
    add_index :friendships, [ :user_id, :position ]
  end
end
