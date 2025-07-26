class CreateIntradayAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :intraday_analyses do |t|
      t.string :symbol
      t.string :timeframe
      t.decimal :atr
      t.decimal :atr_pct
      t.decimal :last_close
      t.datetime :calculated_at

      t.timestamps
    end
    add_index :intraday_analyses, :symbol
    add_index :intraday_analyses, :calculated_at
  end
end
