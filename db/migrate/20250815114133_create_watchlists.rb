class CreateWatchlists < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlists do |t|
      t.string :name, null: false # e.g., 'desk_core_intraday'
      t.string  :kind, null: false              # 'intraday' | 'swing' | 'long_term' | 'custom'
      t.string  :timeframe, null: false         # '15m' | '60m' | '1d'
      t.boolean :active, default: true, null: false
      t.text    :description
      t.jsonb   :meta, null: false, default: {} # thresholds, last run stats, etc.
      t.timestamps
    end
    add_index :watchlists, [:name], unique: true
    add_index :watchlists, %i[kind timeframe]
  end
end
