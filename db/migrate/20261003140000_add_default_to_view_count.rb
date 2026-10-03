# frozen_string_literal: true

class AddDefaultToViewCount < ActiveRecord::Migration[8.1]
  def change
    change_column_default :profiles, :view_count, from: nil, to: 0
  end
end
