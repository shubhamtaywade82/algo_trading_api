class CreateOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders do |t|
      t.string :ticker
      t.string :action
      t.integer :quantity
      t.decimal :price
      t.string :status
      t.string :security_id
      t.string :dhan_order_id
      t.string :dhan_status
      t.decimal :stop_loss_price
      t.decimal :take_profit_price

      t.timestamps
    end
  end
end
