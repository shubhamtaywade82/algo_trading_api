class CreatePositions < ActiveRecord::Migration[8.0]
  def change
    create_table :positions do |t|
      t.string :ticker
      t.string :action
      t.integer :quantity
      t.decimal :entry_price
      t.decimal :stop_loss_price
      t.decimal :take_profit_price
      t.string :security_id
      t.string :status

      t.timestamps
    end
  end
end
