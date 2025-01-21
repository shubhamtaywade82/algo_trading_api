# frozen_string_literal: true

class CreateOrderFeatures < ActiveRecord::Migration[8.0]
  def change
    create_table :order_features do |t|
      t.references :featureable, polymorphic: true, null: false
      t.string :bracket_flag # Y/N
      t.string :cover_flag # Y/N
      t.string :buy_sell_indicator # A for allowed

      t.timestamps
    end
  end
end
