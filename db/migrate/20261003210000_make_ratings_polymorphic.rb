# frozen_string_literal: true

# Reactions move from "somebody's page" onto anything that has been posted.
#
# The old shape could only answer one question — how many people liked this account's page —
# because a rating pointed at a user. That made the rice, a build, a demo, a shot and a link
# all unreactable, which is the wrong way round: on a page like this, the things people
# actually react to are the things somebody posted.
#
# So the pointer becomes a pair: what was reacted to, and which kind of thing it is. A page
# is one of the kinds, so the old rows keep working and keep their meaning.
class MakeRatingsPolymorphic < ActiveRecord::Migration[8.1]
  def up
    add_column :ratings, :rateable_type, :string
    add_column :ratings, :rateable_id, :integer

    # Every existing row is a rating of somebody's page, so it becomes a rating of that
    # account. Nothing is inferred beyond what the row already said.
    execute <<~SQL
      UPDATE ratings
      SET rateable_type = 'User', rateable_id = user_id
      WHERE rateable_type IS NULL
    SQL

    change_column_null :ratings, :rateable_type, false
    change_column_null :ratings, :rateable_id, false

    # The old uniqueness was per page; the new one is per thing reacted to.
    remove_index :ratings, name: "index_ratings_on_user_id_and_author_id"
    remove_index :ratings, name: "index_ratings_on_user_id_and_score"
    remove_column :ratings, :user_id

    add_index :ratings, [ :author_id, :rateable_type, :rateable_id ],
      unique: true, name: "index_ratings_on_author_and_rateable"
    add_index :ratings, [ :rateable_type, :rateable_id ]
  end

  def down
    add_column :ratings, :user_id, :integer

    execute <<~SQL
      UPDATE ratings SET user_id = rateable_id WHERE rateable_type = 'User'
    SQL

    # A rating of anything that is not a page has nowhere to go in the old shape, and
    # silently dropping it is better than writing a row that says something untrue.
    execute "DELETE FROM ratings WHERE user_id IS NULL"

    remove_index :ratings, name: "index_ratings_on_author_and_rateable"
    remove_index :ratings, name: "index_ratings_on_rateable_type_and_rateable_id"
    remove_column :ratings, :rateable_type
    remove_column :ratings, :rateable_id

    change_column_null :ratings, :user_id, false
    add_index :ratings, [ :user_id, :author_id ], unique: true
  end
end
