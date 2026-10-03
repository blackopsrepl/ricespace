class RequireCommentAuthors < ActiveRecord::Migration[8.1]
  # Comments are signed in now, so every comment has an author and there is no typed
  # name. Rows left by the previous anonymous form have no author and no way to get
  # one — a comment with nobody behind it cannot be kept honestly, so they go.
  def up
    execute "DELETE FROM comments WHERE author_id IS NULL"

    change_column_null :comments, :author_id, false
    remove_column :comments, :author_name
  end

  def down
    add_column :comments, :author_name, :string
    change_column_null :comments, :author_id, true
  end
end
