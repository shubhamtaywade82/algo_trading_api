class CreateMarginRequirements < ActiveRecord::Migration[8.0]
  def change
    create_table :margin_requirements do |t|
      t.references :instrument, null: false, foreign_key: true
      t.decimal :buy_co_min_margin_per
      t.decimal :sell_co_min_margin_per
      t.decimal :buy_bo_min_margin_per
      t.decimal :sell_bo_min_margin_per
      t.decimal :buy_co_sl_range_max_perc
      t.decimal :sell_co_sl_range_max_perc
      t.decimal :buy_co_sl_range_min_perc
      t.decimal :sell_co_sl_range_min_perc
      t.decimal :buy_bo_sl_range_max_perc
      t.decimal :sell_bo_sl_range_max_perc
      t.decimal :buy_bo_sl_range_min_perc
      t.decimal :sell_bo_sl_min_range
      t.decimal :buy_bo_profit_range_max_perc
      t.decimal :sell_bo_profit_range_max_perc
      t.decimal :buy_bo_profit_range_min_perc
      t.decimal :sell_bo_profit_range_min_perc

      t.timestamps
    end
  end
end
