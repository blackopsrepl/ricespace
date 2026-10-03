# frozen_string_literal: true

# Favourites are gone, because a favourite was a like with a different noun.
#
# The original had both for a reason: one fed your Top 8 culture and the other fed your page
# score, so they were two counts in two places. There is one ranking here, so there is one
# act — reacting to a page — and a second way to say "I like this page" that appears nowhere
# is a button that does nothing.
class DropFavorites < ActiveRecord::Migration[8.1]
  def up
    drop_table :favorites do |t|
      t.integer "user_id", null: false
      t.integer "favorited_user_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "user_id", "favorited_user_id" ], unique: true
    end
  end

  def down
    create_table :favorites do |t|
      t.integer "user_id", null: false
      t.integer "favorited_user_id", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.index [ "user_id", "favorited_user_id" ], unique: true
    end
  end
end
