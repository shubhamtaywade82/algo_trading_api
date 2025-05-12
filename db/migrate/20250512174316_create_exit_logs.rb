class CreateExitLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :exit_logs do |t|
      t.string :trading_symbol
      t.string :security_id
      t.string :reason
      t.string :order_id
      t.decimal :exit_price
      t.datetime :exit_time

      t.timestamps
    end
  end
end
