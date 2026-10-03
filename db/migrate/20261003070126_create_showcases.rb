class CreateShowcases < ActiveRecord::Migration[8.1]
  def change
    # The showcase: the rice. One per account, and the part of a page that is the point
    # — a screenshot of somebody's Omarchy desktop, what is in it, and how it looks.
    create_table :showcases do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :title
      t.string :summary
      t.text :details, null: false, default: ""

      # The machine and the setup, as separate facts rather than one blob, because a
      # directory of rices is worth having and it can only be filtered by fields.
      t.string :hardware
      t.string :window_manager
      t.string :bar
      t.string :terminal
      t.string :font
      t.string :theme

      t.timestamps
    end

    # The showcase can carry more than one shot: a desktop, a terminal, a phone. The
    # first is the one the page leads with.
    create_table :showcase_shots do |t|
      t.references :showcase, null: false, foreign_key: true
      t.string :caption
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :showcase_shots, [ :showcase_id, :position ]
  end
end
