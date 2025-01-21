# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :dhan_order_id, null: false
      t.string :correlation_id
      t.string :transaction_type, null: false  # BUY, SELL
      t.string :product_type, null: false      # CNC, INTRADAY, MARGIN, MTF, CO, BO
      t.string :order_type, null: false        # LIMIT, MARKET, STOP_LOSS, STOP_LOSS_MARKET
      t.string :validity                      # DAY, IOC
      t.string :exchange_segment              # NSE_EQ, NSE_FNO, etc.
      t.string :security_id, null: false
      t.integer :quantity, null: false
      t.integer :disclosed_quantity
      t.decimal :price, precision: 15, scale: 2
      t.decimal :trigger_price, precision: 15, scale: 2
      t.decimal :bo_profit_value, precision: 15, scale: 2
      t.decimal :bo_stop_loss_value, precision: 15, scale: 2
      t.decimal :ltp, precision: 15, scale: 2 # Last Traded Price
      t.string :order_status                  # PENDING, REJECTED, CANCELLED, TRADED, EXPIRED
      t.integer :filled_qty
      t.decimal :average_traded_price, precision: 15, scale: 2
      t.references :alert, foreign_key: true
      t.timestamps
    end
  end
end
