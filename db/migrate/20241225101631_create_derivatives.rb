# frozen_string_literal: true

class CreateDerivatives < ActiveRecord::Migration[8.0]
  def change
    create_table :derivatives do |t|
      t.references :instrument, null: false, foreign_key: true
      t.decimal :strike_price
      t.string :option_type # CE, PE
      t.date :expiry_date
      t.string :expiry_flag # M, W

      t.timestamps
    end
  end
end
