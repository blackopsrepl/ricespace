# frozen_string_literal: true

# The wall moves onto whatever was posted.
#
# A comment pointed at a user, so the only place to write was somebody's page. But the thing
# a person wants to answer is usually the thing that was posted — the rice, the build, the
# demo — and a page-level wall forces every answer to the top of the page and away from what
# it is about.
#
# So a comment points at any postable thing. A page is one of them, so the old rows keep
# working.
class MakeCommentsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :comments, :commentable_type, :string
    add_column :comments, :commentable_id, :integer

    execute <<~SQL
      UPDATE comments
      SET commentable_type = 'User', commentable_id = user_id
      WHERE commentable_type IS NULL
    SQL

    change_column_null :comments, :commentable_type, false
    change_column_null :comments, :commentable_id, false

    remove_index :comments, :user_id if index_exists?(:comments, :user_id)
    remove_column :comments, :user_id

    add_index :comments, [ :commentable_type, :commentable_id, :created_at ],
      name: "index_comments_on_commentable_and_time"
    add_index :comments, :author_id unless index_exists?(:comments, :author_id)
  end

  def down
    add_column :comments, :user_id, :integer

    execute <<~SQL
      UPDATE comments SET user_id = commentable_id WHERE commentable_type = 'User'
    SQL

    execute "DELETE FROM comments WHERE user_id IS NULL"

    remove_index :comments, name: "index_comments_on_commentable_and_time"
    remove_index :comments, :author_id
    remove_column :comments, :commentable_type
    remove_column :comments, :commentable_id

    change_column_null :comments, :user_id, false
    add_index :comments, :user_id
  end
end
