class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :document, null: false, default: ""
      t.timestamps
    end

    # Two editors — the owner in a browser and the owner's agent over the API —
    # can hold the same page at once. The version is bumped on every content
    # change so each of them can say which revision it edited, and a write based
    # on an old one can be refused instead of silently winning.
    add_column :profiles, :version, :integer, null: false, default: 0
  end
end
