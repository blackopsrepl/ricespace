class CreateStreamLinks < ActiveRecord::Migration[8.1]
  def change
    # A video or stream shown on a page. Nothing is stored: this is the link, plus the
    # little that had to be read out of it to build an embed. `platform` and `reference`
    # are what the embed is built from, so a page never renders a URL its owner pasted.
    create_table :stream_links do |t|
      t.references :user, null: false, foreign_key: true

      # What was pasted, kept verbatim so the owner can see and edit what they entered
      # and so a change of platform parsing can be checked against the original.
      t.string :url, null: false

      # Read out of the url: which service, and which video/channel on it.
      t.string :platform, null: false
      t.string :reference, null: false
      t.string :title

      t.timestamps
    end

    # One clip per service per page. The rule is enforced here as well as in the model,
    # so a race cannot leave a page with two of the same thing.
    add_index :stream_links, [ :user_id, :platform ], unique: true
  end
end
