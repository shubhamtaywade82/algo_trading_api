class CreateHoldings < ActiveRecord::Migration[8.0]
  def change
    create_table :holdings do |t|
      t.string :exchange
      t.string :trading_symbol, null: false
      t.string :security_id, null: false
      t.string :isin, null: false
      t.integer :total_qty, null: false
      t.integer :dp_qty                   # Delivered quantity
      t.integer :t1_qty                   # Pending delivery quantity
      t.integer :available_qty, null: false
      t.integer :collateral_qty
      t.decimal :avg_cost_price, precision: 15, scale: 2, null: false
      t.timestamps
    end
  end
end
