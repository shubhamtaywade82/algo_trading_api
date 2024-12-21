class CreateStrategies < ActiveRecord::Migration[8.0]
  def change
    create_table :strategies do |t|
      t.string :name, null: false
      t.text :objective
      t.text :how_it_works
      t.text :risk
      t.text :reward
      t.text :best_used_when
      t.text :example
      t.timestamps
    end
  end
end
