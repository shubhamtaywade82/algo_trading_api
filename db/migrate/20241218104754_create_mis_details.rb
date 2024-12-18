class CreateMisDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :mis_details do |t|
      t.references :instrument, null: false, foreign_key: true
      t.string :isin
      t.decimal :mis_leverage
      t.decimal :bo_leverage
      t.decimal :co_leverage

      t.timestamps
    end
  end
end
