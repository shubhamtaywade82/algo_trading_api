class CreateExchanges < ActiveRecord::Migration[8.0]
  def change
    create_table :exchanges do |t|
      t.string :exch_id
      t.string :name

      t.timestamps
    end
  end
end
