# frozen_string_literal: true

class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table :positions do |t|
      t.references :instrument, foreign_key: true
      t.string :trading_symbol, null: false
      t.string :security_id, null: false
      t.string :position_type, null: false # LONG, SHORT, CLOSED
      t.string :exchange_segment               # NSE_EQ, NSE_FNO, etc.
      t.string :product_type, null: false      # CNC, INTRADAY, etc.
      t.decimal :buy_avg, precision: 15, scale: 2
      t.decimal :sell_avg, precision: 15, scale: 2
      t.integer :buy_qty
      t.integer :sell_qty
      t.integer :net_qty
      t.decimal :cost_price, precision: 15, scale: 2
      t.decimal :realized_profit, precision: 15, scale: 2
      t.decimal :unrealized_profit, precision: 15, scale: 2
      t.decimal :rbi_reference_rate, precision: 15, scale: 2
      t.timestamps
    end
  end
end
