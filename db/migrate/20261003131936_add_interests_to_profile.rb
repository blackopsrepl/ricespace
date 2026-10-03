# frozen_string_literal: true

class AddInterestsToProfile < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :interests, :json, default: {}
  end
end
