class CreateSwingPicks < ActiveRecord::Migration[8.0]
  def change
    create_table :swing_picks do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :setup_type
      t.decimal :trigger_price
      t.decimal :close_price
      t.decimal :ema
      t.decimal :rsi
      t.bigint :volume
      t.text :analysis
      t.integer :status

      t.timestamps
    end
  end
end
