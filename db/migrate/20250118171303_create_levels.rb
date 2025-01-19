class CreateLevels < ActiveRecord::Migration[8.0]
  def change
    create_table :levels do |t|
      t.references :instrument, null: false, foreign_key: true
      t.decimal :high
      t.decimal :low
      t.decimal :open
      t.decimal :close
      t.decimal :volume
      t.decimal :demand_zone
      t.decimal :supply_zone
      t.string :timeframe
      t.date :period_start
      t.date :period_end

      t.timestamps
    end
  end
end
