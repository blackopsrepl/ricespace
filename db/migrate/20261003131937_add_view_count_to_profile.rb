class AddViewCountToProfile < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :view_count, :integer
  end
end
