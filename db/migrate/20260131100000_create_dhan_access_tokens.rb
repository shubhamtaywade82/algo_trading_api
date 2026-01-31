# frozen_string_literal: true

class CreateDhanAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :dhan_access_tokens do |t|
      t.string :access_token, null: false
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :dhan_access_tokens, :expires_at
  end
end
