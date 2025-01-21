# frozen_string_literal: true

class CreateDerivatives < ActiveRecord::Migration[8.0]
  def change
    create_table :derivatives do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :exchange, null: false
      t.string :segment, null: false
      t.string :security_id, null: false
      t.string :symbol_name, null: false
      t.string :display_name
      t.string :instrument
      t.string :instrument_type
      t.string :underlying_security_id
      t.string :underlying_symbol
      t.date :expiry_date
      t.decimal :strike_price, precision: 15, scale: 5
      t.string :option_type # CE, PE
      t.integer :lot_size
      t.string :expiry_flag # M, W
      t.decimal :tick_size, precision: 10, scale: 5
      t.boolean :asm_gsm_flag, default: false

      t.timestamps
    end

    add_index :derivatives, %i[security_id symbol_name exchange segment], unique: true, name: 'index_derivatives_unique'
  end
end
