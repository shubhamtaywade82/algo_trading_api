class CreateAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :alerts do |t|
      t.string :ticker, null: false
      t.string :instrument_type, null: false
      t.string :order_type, null: false
      t.string :current_position
      t.string :previous_position
      t.decimal :current_price, precision: 15, scale: 2, null: false
      t.decimal :high, precision: 15, scale: 2
      t.decimal :low, precision: 15, scale: 2
      t.decimal :volume, precision: 15, scale: 6
      t.datetime :time, null: false
      t.string :chart_interval
      t.decimal :stop_loss, precision: 15, scale: 2
      t.decimal :take_profit, precision: 15, scale: 2
      t.decimal :trailing_stop_loss, precision: 15, scale: 2
      t.string :strategy_name, null: false
      t.string :strategy_id, null: false

      t.timestamps
    end

    # Add indexes for efficient querying
    add_index :alerts, :ticker
    add_index :alerts, :instrument_type
    add_index :alerts, :strategy_id
  end
end
