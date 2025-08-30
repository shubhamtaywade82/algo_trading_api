class CreateWatchlistItems < ActiveRecord::Migration[8.0]
  def change
    create_table :watchlist_items do |t|
      t.references :watchlist,  null: false, foreign_key: true
      t.references :instrument, null: false, foreign_key: true

      t.integer :rank, null: false, default: 0
      t.string  :bucket, null: false, default: 'intraday' # intraday/swing/long_term

      # Derivative availability flags
      t.boolean :has_derivatives, null: false, default: false
      t.boolean :has_options,     null: false, default: false
      t.boolean :has_futures,     null: false, default: false

      # Optional signal state
      t.datetime :last_scored_at
      t.jsonb :metrics, null: false, default: {} # e.g., {rsi14:.., atr_pct:.., rel_vol:.., score:..}

      t.timestamps
    end

    add_index :watchlist_items, %i[watchlist_id instrument_id], unique: true, name: 'idx_watchlist_items_uni'
    add_index :watchlist_items, %i[watchlist_id rank]
    add_index :watchlist_items, [:bucket]
  end
end
