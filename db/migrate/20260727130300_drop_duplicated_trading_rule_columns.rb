# frozen_string_literal: true

# Drops the 22 trading-rule columns now owned by `order_features` and
# `margin_requirements` (see the preceding backfill migration) from both wide
# tables.
#
# These were dead weight on the two tables every tick, every order and every
# option-chain read touches: the importer never wrote 16 of the 22, and the
# other six now live in the satellites that were built for them.
class DropDuplicatedTradingRuleColumns < ActiveRecord::Migration[8.0]
  FLAG_COLUMNS = {
    bracket_flag: :string,
    cover_flag: :string,
    asm_gsm_flag: :string,
    asm_gsm_category: :string,
    buy_sell_indicator: :string
  }.freeze

  MARGIN_COLUMNS = %i[
    buy_co_min_margin_per sell_co_min_margin_per
    buy_co_sl_range_max_perc sell_co_sl_range_max_perc
    buy_co_sl_range_min_perc sell_co_sl_range_min_perc
    buy_bo_min_margin_per sell_bo_min_margin_per
    buy_bo_sl_range_max_perc sell_bo_sl_range_max_perc
    buy_bo_sl_range_min_perc sell_bo_sl_min_range
    buy_bo_profit_range_max_perc sell_bo_profit_range_max_perc
    buy_bo_profit_range_min_perc sell_bo_profit_range_min_perc
    mtf_leverage
  ].freeze

  def change
    %i[instruments derivatives].each do |table|
      FLAG_COLUMNS.each { |column, type| remove_column table, column, type }
      MARGIN_COLUMNS.each do |column|
        remove_column table, column, :decimal, precision: 8, scale: 2
      end
    end
  end
end
