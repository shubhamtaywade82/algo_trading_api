class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :security_id, null: false
      t.string :isin
      t.string :instrument
      t.string :instrument_type
      t.string :underlying_security_id
      t.string :underlying_symbol
      t.string :symbol_name
      t.string :display_name
      t.string :series
      t.integer :lot_size
      t.decimal :tick_size, precision: 10, scale: 4
      t.string :asm_gsm_flag
      t.string :asm_gsm_category
      t.decimal :mtf_leverage, precision: 5, scale: 2
      t.string :exchange, null: false
      t.string :segment, null: false

      t.timestamps
    end

    add_index :instruments, :security_id
    add_index :instruments, :instrument
  end
end
