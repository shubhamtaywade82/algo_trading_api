class CreateExchangeSegments < ActiveRecord::Migration[8.0]
  def change
    create_table :exchange_segments do |t|
      t.references :exchange, null: false, foreign_key: true
      t.references :segment, null: false, foreign_key: true
      t.string :exchange_segment, null: false

      t.timestamps
    end
  end
end
