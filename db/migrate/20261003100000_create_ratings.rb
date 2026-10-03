class CreateRatings < ActiveRecord::Migration[8.1]
  def change
    # One row per account per page: like or dislike, not a count. The era's sites had a
    # single "like this page" and that is what this is — a score is not a number of
    # clicks, it is how many people said yes.
    create_table :ratings do |t|
      t.integer :user_id, null: false          # the page being rated
      t.integer :author_id, null: false        # the account doing the rating
      t.integer :score, null: false, default: 1 # 1 like, -1 dislike

      t.timestamps
    end

    # One account rates a page once. Changing your mind updates the row rather than
    # adding a second opinion, which is what makes the number mean "people" rather than
    # "clicks".
    add_index :ratings, [ :user_id, :author_id ], unique: true
    add_index :ratings, :author_id
    add_index :ratings, [ :user_id, :score ]

    add_foreign_key :ratings, :users
    add_foreign_key :ratings, :users, column: :author_id
  end
end
