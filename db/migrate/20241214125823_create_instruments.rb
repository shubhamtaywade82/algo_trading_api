class CreateInstruments < ActiveRecord::Migration[8.0]
  def change
    create_table :instruments do |t|
      t.string :exch_id
      t.string :segment
      t.string :security_id
      t.string :isin
      t.string :instrument
      t.string :underlying_symbol
      t.string :symbol_name
      t.string :display_name
      t.string :instrument_type
      t.integer :lot_size
      t.date :sm_expiry_date
      t.decimal :strike_price, precision: 10, scale: 2
      t.string :option_type
      t.decimal :tick_size, precision: 10, scale: 2
      t.string :expiry_flag
      t.string :asm_gsm_flag
      t.decimal :buy_co_min_margin_per, precision: 10, scale: 2
      t.decimal :sell_co_min_margin_per, precision: 10, scale: 2
      t.decimal :buy_bo_min_margin_per, precision: 10, scale: 2
      t.decimal :sell_bo_min_margin_per, precision: 10, scale: 2
      t.decimal :mtf_leverage, precision: 10, scale: 2

      t.timestamps
    end

    add_index :instruments, :security_id, unique: true
  end
end
