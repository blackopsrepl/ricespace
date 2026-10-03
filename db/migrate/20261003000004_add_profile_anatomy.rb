class AddProfileAnatomy < ActiveRecord::Migration[8.1]
  def change
    # The parts of an account a profile page shows that are not its markup: the
    # greeting across the top, the mood, and the picture beside the name.
    change_table :users, bulk: true do |t|
      t.string :greeting
      t.string :mood
    end

    # A friend: somebody on this account's friends list. The list is the account's
    # own, so the row is stored on the page that shows it.
    create_table :friendships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :friend, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :friendships, [ :user_id, :friend_id ], unique: true

    # A blurb is a titled piece of text — what the era called Interests, Music,
    # Heroes — so a page can be built out of them without the owner writing a
    # whole layout for each one.
    create_table :blurbs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :blurbs, [ :user_id, :position ]

    # A comment: text a visitor left on this page. The body is plain text, so a
    # comment can never restyle the page it is written on.
    create_table :comments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :author, foreign_key: { to_table: :users }
      t.string :author_name
      t.text :body, null: false

      t.timestamps
    end

    add_index :comments, [ :user_id, :created_at ]

    # A profile picture is an upload, not a URL the owner types: the era's pages
    # were photographs, and asking someone to host their own was the friction that
    # lost them at that step elsewhere.
    create_table :profile_pictures do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.timestamps
    end
  end
end
