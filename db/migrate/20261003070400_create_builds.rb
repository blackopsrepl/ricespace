class CreateBuilds < ActiveRecord::Migration[8.1]
  def change
    # The hardware on a page: a physical build, its photos, and what is in it. Same shape
    # as the showcase, because it is the same kind of thing — a picture of something
    # somebody made, plus the facts that make it worth looking at.
    create_table :builds do |t|
      t.references :user, null: false, foreign_key: true

      t.string :title, null: false
      # A small vocabulary rather than free text, so a list of builds can be read as a
      # column rather than parsed.
      t.string :kind
      t.string :summary
      t.text :details, null: false, default: ""
      # The two facts somebody always asks about physical hardware.
      t.string :specs
      t.string :cooling

      t.timestamps
    end

    create_table :build_photos do |t|
      t.references :build, null: false, foreign_key: true
      t.string :caption
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :build_photos, [ :build_id, :position ]
  end
end
