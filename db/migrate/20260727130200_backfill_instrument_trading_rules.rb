# frozen_string_literal: true

# Moves the scrip master's trading-rule columns into the satellite tables that
# already exist for them.
#
# `margin_requirements` and `order_features` were created in the original
# schema as polymorphic satellites of Instrument/Derivative, and then never
# written to: InstrumentsImport::Parser builds one flat hash and slices it by
# `Instrument.column_names`, so all 24 rule columns were duplicated onto both
# wide tables instead. The result is 24 columns × 2 tables that are almost
# entirely NULL (the parser only ever filled asm_gsm_flag, asm_gsm_category and
# mtf_leverage) sitting in the middle of the two hottest tables in the app.
#
# This backfills the satellites from whatever the wide columns hold today; the
# next migration drops the duplicates.
class BackfillInstrumentTradingRules < ActiveRecord::Migration[8.0]
  # ASM/GSM surveillance status and MTF leverage are tradability facts, so they
  # belong with the bracket/cover flags rather than with the margin percentages.
  def change
    add_column :order_features, :asm_gsm_flag, :string
    add_column :order_features, :asm_gsm_category, :string
    add_column :order_features, :mtf_leverage, :decimal, precision: 8, scale: 2

    # Needed as an upsert conflict target, and a satellite is 1:1 with its
    # owner by definition — the original index allowed duplicates.
    reversible do |dir|
      dir.up { deduplicate_order_features! }
    end

    remove_index :order_features, column: %i[featureable_type featureable_id],
                                  name: 'index_order_features_on_featureable'
    add_index :order_features, %i[featureable_type featureable_id],
              unique: true, name: 'index_order_features_on_featureable'

    reversible do |dir|
      dir.up do
        %w[Instrument Derivative].each do |owner|
          backfill_order_features!(owner)
          backfill_margin_requirements!(owner)
        end
      end
    end
  end

  private

  def table_for(owner)
    owner == 'Instrument' ? 'instruments' : 'derivatives'
  end

  def deduplicate_order_features!
    execute(<<~SQL.squish)
      DELETE FROM order_features a
      USING order_features b
      WHERE a.featureable_type = b.featureable_type
        AND a.featureable_id = b.featureable_id
        AND a.id < b.id
    SQL
  end

  def backfill_order_features!(owner)
    table = table_for(owner)
    # `derivatives.asm_gsm_flag` holds "true"/"false" on rows written by the
    # pre-fix parser, which assigned a boolean into a string column. Normalise
    # those back to the exchange's own Y/N while the data moves.
    execute(<<~SQL.squish)
      INSERT INTO order_features
        (featureable_type, featureable_id, bracket_flag, cover_flag, buy_sell_indicator,
         asm_gsm_flag, asm_gsm_category, mtf_leverage, created_at, updated_at)
      SELECT '#{owner}', s.id, s.bracket_flag, s.cover_flag, s.buy_sell_indicator,
             CASE s.asm_gsm_flag WHEN 'true' THEN 'Y' WHEN 'false' THEN 'N' ELSE s.asm_gsm_flag END,
             s.asm_gsm_category, s.mtf_leverage, NOW(), NOW()
      FROM #{table} s
      WHERE COALESCE(s.bracket_flag, s.cover_flag, s.buy_sell_indicator,
                     s.asm_gsm_flag, s.asm_gsm_category) IS NOT NULL
         OR s.mtf_leverage IS NOT NULL
      ON CONFLICT (featureable_type, featureable_id) DO UPDATE SET
        bracket_flag = EXCLUDED.bracket_flag,
        cover_flag = EXCLUDED.cover_flag,
        buy_sell_indicator = EXCLUDED.buy_sell_indicator,
        asm_gsm_flag = EXCLUDED.asm_gsm_flag,
        asm_gsm_category = EXCLUDED.asm_gsm_category,
        mtf_leverage = EXCLUDED.mtf_leverage,
        updated_at = NOW()
    SQL
  end

  MARGIN_COLUMNS = %w[
    buy_co_min_margin_per sell_co_min_margin_per
    buy_co_sl_range_max_perc sell_co_sl_range_max_perc
    buy_co_sl_range_min_perc sell_co_sl_range_min_perc
    buy_bo_min_margin_per sell_bo_min_margin_per
    buy_bo_sl_range_max_perc sell_bo_sl_range_max_perc
    buy_bo_sl_range_min_perc sell_bo_sl_min_range
    buy_bo_profit_range_max_perc sell_bo_profit_range_max_perc
    buy_bo_profit_range_min_perc sell_bo_profit_range_min_perc
  ].freeze

  def backfill_margin_requirements!(owner)
    table = table_for(owner)
    selected = MARGIN_COLUMNS.map { |c| "s.#{c}" }.join(', ')
    assignments = MARGIN_COLUMNS.map { |c| "#{c} = EXCLUDED.#{c}" }.join(', ')

    execute(<<~SQL.squish)
      INSERT INTO margin_requirements
        (requirementable_type, requirementable_id, #{MARGIN_COLUMNS.join(', ')}, created_at, updated_at)
      SELECT '#{owner}', s.id, #{selected}, NOW(), NOW()
      FROM #{table} s
      WHERE COALESCE(#{selected}) IS NOT NULL
      ON CONFLICT (requirementable_type, requirementable_id) DO UPDATE SET
        #{assignments}, updated_at = NOW()
    SQL
  end
end
