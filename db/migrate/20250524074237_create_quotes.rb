class CreateQuotes < ActiveRecord::Migration[8.0]
  def change
    create_table :quotes do |t|
      t.references :instrument, null: false, foreign_key: true
      t.decimal :ltp
      t.bigint :volume
      t.datetime :tick_time
      t.jsonb :metadata

      t.timestamps
    end
  end
end
