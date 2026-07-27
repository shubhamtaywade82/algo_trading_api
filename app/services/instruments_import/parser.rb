# frozen_string_literal: true

require 'csv'

module InstrumentsImport
  # Parses the detailed scrip master and splits each row into the tables that
  # own its columns: identity and contract data onto `instruments` or
  # `derivatives`, tradability flags onto `order_features`, CO/BO percentages
  # onto `margin_requirements`.
  #
  # Satellite rows travel alongside their owner keyed by the owner's natural
  # key, because the owner's primary key does not exist until the Upserter has
  # run.
  class Parser < ApplicationService
    VALID_EXCHANGES = %w[NSE BSE MCX].freeze

    # Detailed-CSV column => order_features column.
    FEATURE_COLUMNS = {
      'BRACKET_FLAG' => :bracket_flag,
      'COVER_FLAG' => :cover_flag,
      'BUY_SELL_INDICATOR' => :buy_sell_indicator,
      'ASM_GSM_FLAG' => :asm_gsm_flag,
      'ASM_GSM_CATEGORY' => :asm_gsm_category
    }.freeze

    # Detailed-CSV column => margin_requirements column. SELL_BO_SL_MIN_RANGE
    # is the scrip master's own inconsistency — every sibling ends in _PERC.
    MARGIN_COLUMNS = {
      'BUY_CO_MIN_MARGIN_PER' => :buy_co_min_margin_per,
      'SELL_CO_MIN_MARGIN_PER' => :sell_co_min_margin_per,
      'BUY_CO_SL_RANGE_MAX_PERC' => :buy_co_sl_range_max_perc,
      'SELL_CO_SL_RANGE_MAX_PERC' => :sell_co_sl_range_max_perc,
      'BUY_CO_SL_RANGE_MIN_PERC' => :buy_co_sl_range_min_perc,
      'SELL_CO_SL_RANGE_MIN_PERC' => :sell_co_sl_range_min_perc,
      'BUY_BO_MIN_MARGIN_PER' => :buy_bo_min_margin_per,
      'SELL_BO_MIN_MARGIN_PER' => :sell_bo_min_margin_per,
      'BUY_BO_SL_RANGE_MAX_PERC' => :buy_bo_sl_range_max_perc,
      'SELL_BO_SL_RANGE_MAX_PERC' => :sell_bo_sl_range_max_perc,
      'BUY_BO_SL_RANGE_MIN_PERC' => :buy_bo_sl_range_min_perc,
      'SELL_BO_SL_MIN_RANGE' => :sell_bo_sl_min_range,
      'BUY_BO_PROFIT_RANGE_MAX_PERC' => :buy_bo_profit_range_max_perc,
      'SELL_BO_PROFIT_RANGE_MAX_PERC' => :sell_bo_profit_range_max_perc,
      'BUY_BO_PROFIT_RANGE_MIN_PERC' => :buy_bo_profit_range_min_perc,
      'SELL_BO_PROFIT_RANGE_MIN_PERC' => :sell_bo_profit_range_min_perc
    }.freeze

    # The tuple the upserts conflict on. Satellites carry it so they can be
    # attached to their owner once the owner has an id.
    def self.natural_key(attrs)
      [attrs[:security_id].to_s, attrs[:symbol_name].to_s,
       attrs[:exchange].to_s, attrs[:segment].to_s]
    end

    def initialize(csv_content)
      @csv_content = csv_content
    end

    def call
      instruments = []
      derivatives = []
      features = []
      margins = []

      # Streamed rather than CSV.parse'd: the detailed master is well over a
      # hundred thousand rows and CSV.parse materialises every one as a
      # CSV::Row before the first is looked at.
      CSV.new(@csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])

        attrs = build_attrs(row)
        derivative = row['SEGMENT'] == 'D'
        owner_type = derivative ? 'Derivative' : 'Instrument'
        key = self.class.natural_key(attrs)

        if derivative
          derivatives << attrs.slice(*derivative_column_symbols)
        else
          instruments << attrs.slice(*instrument_column_symbols)
        end

        if (feature = build_feature(row))
          features << feature.merge(owner_type: owner_type, owner_key: key)
        end
        if (margin = build_margin(row))
          margins << margin.merge(owner_type: owner_type, owner_key: key)
        end
      end

      { instruments: instruments, derivatives: derivatives,
        order_features: features, margin_requirements: margins }
    end

    private

    def instrument_column_symbols
      # exchange_segment is a generated column — Postgres rejects any attempt
      # to write it.
      @instrument_column_symbols ||= (Instrument.column_names - %w[id exchange_segment]).map(&:to_sym).freeze
    end

    def derivative_column_symbols
      @derivative_column_symbols ||= (Derivative.column_names - %w[id exchange_segment]).map(&:to_sym).freeze
    end

    def build_attrs(row)
      now = Time.zone.now
      lot = row['LOT_SIZE'].to_s.strip
      lot_size = lot.to_i.positive? ? lot.to_i : nil

      {
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        security_id: row['SECURITY_ID'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        isin: row['ISIN'],
        instrument_code: row['INSTRUMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        series: row['SERIES'],
        lot_size: lot_size,
        tick_size: safe_float(row['TICK_SIZE']),
        expiry_date: safe_date(row['SM_EXPIRY_DATE']),
        strike_price: safe_float(row['STRIKE_PRICE']),
        option_type: option_type_for(row),
        expiry_flag: row['EXPIRY_FLAG'],
        # Present in this feed, so tradable and seen now. The staleness sweep
        # flips `active` on whatever the feed stopped listing.
        active: true,
        last_seen_at: now,
        created_at: now,
        updated_at: now
      }
    end

    # MCX ships OPTION_TYPE = "XX" on futures rows (GOLD FEB FUT and friends),
    # which is the exchange's way of saying "not an option". Stored verbatim it
    # satisfies neither `Derivative#option?` nor the `futures` scope, so those
    # contracts fell through both — and it is the one value that breaks the
    # CE/PE CHECK constraint. Only a real option type survives.
    def option_type_for(row)
      value = row['OPTION_TYPE'].to_s.strip.upcase
      Derivative::OPTION_TYPES.include?(value) ? value : nil
    end

    def build_feature(row)
      attrs = FEATURE_COLUMNS.each_with_object({}) do |(csv_column, attribute), acc|
        # Previously `asm_gsm_flag` was assigned `row['ASM_GSM_FLAG'] == 'Y'`
        # for derivatives — a boolean into a string column, which Postgres
        # stored as "true"/"false" and no Y/N comparison ever matched.
        acc[attribute] = row[csv_column].to_s.strip.presence
      end
      attrs[:mtf_leverage] = safe_float(row['MTF_LEVERAGE'])
      return nil if attrs.values.all?(&:nil?)

      attrs
    end

    def build_margin(row)
      attrs = MARGIN_COLUMNS.each_with_object({}) do |(csv_column, attribute), acc|
        acc[attribute] = safe_float(row[csv_column])
      end
      return nil if attrs.values.all?(&:nil?)

      attrs
    end

    def safe_date(str)
      Date.parse(str.to_s)
    rescue StandardError
      nil
    end

    def safe_float(val)
      val.to_s.strip.empty? ? nil : val.to_f
    end
  end
end
