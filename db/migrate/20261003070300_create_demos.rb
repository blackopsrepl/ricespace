class CreateDemos < ActiveRecord::Migration[8.1]
  def change
    # A demoscene demo listed on a page, and the release facts that make it worth
    # listing: who made it, where it was released, what it ran on, and what it won.
    create_table :demos do |t|
      t.references :user, null: false, foreign_key: true

      t.string :title, null: false
      t.string :group_name
      t.string :party
      t.integer :release_year
      t.string :platform
      t.string :category
      t.integer :ranking

      # Where to watch it. A demo is a video, so this is read the same way as any other
      # video on a page — see VideoSource. It may be a catalogue page instead, in which
      # case there is no embed and the link stands on its own.
      t.string :url
      t.string :watch_note

      t.timestamps
    end

    add_index :demos, [ :user_id, :title ]
  end
end
