# frozen_string_literal: true

require 'csv'
require 'open-uri'
require_relative '../../lib/instrument_type_mapping'
require_relative '../../lib/setting'

class InstrumentsImporter
  CSV_URL         = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH      = Rails.root.join('tmp/dhan_scrip_master.csv')
  CACHE_MAX_AGE   = 24.hours
  VALID_EXCHANGES = %w[NSE BSE].freeze
  BATCH_SIZE      = 1_000

  class << self
    # ------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------
    def import_from_url
      started_at = Time.current
      csv_text   = fetch_csv_with_cache
      summary    = import_from_csv(csv_text)
      finished_at = Time.current

      summary[:started_at]  = started_at
      summary[:finished_at] = finished_at
      summary[:duration]    = finished_at - started_at

      record_success!(summary)

      summary
    end

    # ------------------------------------------------------------
    # Fetch CSV with 24-hour cache
    # ------------------------------------------------------------
    def fetch_csv_with_cache
      if CACHE_PATH.exist? && Time.current - CACHE_PATH.mtime < CACHE_MAX_AGE
        return CACHE_PATH.read
      end

      csv_text = URI.open(CSV_URL, &:read) # rubocop:disable Security/Open
      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)

      csv_text
    rescue StandardError => e
      raise e if CACHE_PATH.exist? == false # don't swallow if no fallback
      CACHE_PATH.read # fallback to cached file
    end

    private :fetch_csv_with_cache

    def import_from_csv(csv_content)
      instruments_rows, derivatives_rows = build_batches(csv_content)

      instrument_import = instruments_rows.empty? ? nil : import_instruments!(instruments_rows)
      derivative_import = derivatives_rows.empty? ? nil : import_derivatives!(derivatives_rows)

      {
        instrument_rows: instruments_rows.size,
        derivative_rows: derivatives_rows.size,
        instrument_upserts: instrument_import&.ids&.size.to_i,
        derivative_upserts: derivative_import&.ids&.size.to_i,
        instrument_total: Instrument.count,
        derivative_total: Derivative.count
      }
    end

    private

    # ------------------------------------------------------------
    # 1. Split CSV rows
    # ------------------------------------------------------------
    def build_batches(csv_content)
      instruments = []
      derivatives = []

      CSV.parse(csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])

        attrs = build_attrs(row)

        if row['SEGMENT'] == 'D' # Derivative
          derivatives << attrs.slice(*Derivative.column_names.map(&:to_sym))
        else # Cash / Index
          instruments << attrs.slice(*Instrument.column_names.map(&:to_sym))
        end
      end

      [instruments, derivatives]
    end

    def build_attrs(row)
      now = Time.zone.now
      csv_instrument = row['INSTRUMENT'].to_s.upcase

      {
        security_id: row['SECURITY_ID'],
        exchange: map_exchange(row['EXCH_ID']),
        segment: map_segment(row['SEGMENT']),
        isin: row['ISIN'],
        instrument_code: map_instrument_code_to_enum_key(csv_instrument),
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        instrument_type: row['INSTRUMENT_TYPE'],
        series: row['SERIES'],
        lot_size: row['LOT_SIZE']&.to_i,
        expiry_date: safe_date(row['SM_EXPIRY_DATE']),
        strike_price: row['STRIKE_PRICE']&.to_f,
        option_type: row['OPTION_TYPE'],
        tick_size: row['TICK_SIZE']&.to_f,
        expiry_flag: row['EXPIRY_FLAG'],
        bracket_flag: row['BRACKET_FLAG'],
        cover_flag: row['COVER_FLAG'],
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        buy_sell_indicator: row['BUY_SELL_INDICATOR'],
        buy_co_min_margin_per: row['BUY_CO_MIN_MARGIN_PER']&.to_f,
        sell_co_min_margin_per: row['SELL_CO_MIN_MARGIN_PER']&.to_f,
        buy_co_sl_range_max_perc: row['BUY_CO_SL_RANGE_MAX_PERC']&.to_f,
        sell_co_sl_range_max_perc: row['SELL_CO_SL_RANGE_MAX_PERC']&.to_f,
        buy_co_sl_range_min_perc: row['BUY_CO_SL_RANGE_MIN_PERC']&.to_f,
        sell_co_sl_range_min_perc: row['SELL_CO_SL_RANGE_MIN_PERC']&.to_f,
        buy_bo_min_margin_per: row['BUY_BO_MIN_MARGIN_PER']&.to_f,
        sell_bo_min_margin_per: row['SELL_BO_MIN_MARGIN_PER']&.to_f,
        buy_bo_sl_range_max_perc: row['BUY_BO_SL_RANGE_MAX_PERC']&.to_f,
        sell_bo_sl_range_max_perc: row['SELL_BO_SL_RANGE_MAX_PERC']&.to_f,
        buy_bo_sl_range_min_perc: row['BUY_BO_SL_RANGE_MIN_PERC']&.to_f,
        sell_bo_sl_min_range: row['SELL_BO_SL_MIN_RANGE']&.to_f,
        buy_bo_profit_range_max_perc: row['BUY_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        sell_bo_profit_range_max_perc: row['SELL_BO_PROFIT_RANGE_MAX_PERC']&.to_f,
        buy_bo_profit_range_min_perc: row['BUY_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        sell_bo_profit_range_min_perc: row['SELL_BO_PROFIT_RANGE_MIN_PERC']&.to_f,
        mtf_leverage: row['MTF_LEVERAGE']&.to_f,
        created_at: now,
        updated_at: now
      }
    end

    # ------------------------------------------------------------
    # 3. Upsert instruments
    # ------------------------------------------------------------
    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[
            display_name isin instrument_code instrument_type
            underlying_symbol lot_size tick_size updated_at
          ]
        }
      )
    end

    # ------------------------------------------------------------
    # 4. Upsert derivatives
    # ------------------------------------------------------------
    def import_derivatives!(rows)
      with_parent, without_parent = attach_instrument_ids(rows)

      return if with_parent.empty?

      Derivative.import(
        with_parent,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[
            symbol_name display_name isin instrument_code instrument_type
            underlying_symbol series lot_size tick_size updated_at
          ]
        }
      )
    end

    # ------------------------------------------------------------
    # 4a. Attach instrument_id to each derivative row
    # ------------------------------------------------------------
    def attach_instrument_ids(rows)
      # Build lookup: [instrument_code (CSV value), underlying_symbol] => instrument_id
      # Note: instrument_code in DB stores the enum value (e.g., 'INDEX'), not the key
      lookup = Instrument.pluck(
        :id, :instrument_code, :underlying_symbol, :exchange, :segment
      ).each_with_object({}) do |(id, db_value, sym, _exch, _seg), h|
        next if sym.blank?

        # db_value is the enum value (e.g., 'INDEX'), which is what we need for lookup
        csv_code = db_value.to_s.upcase
        key      = [csv_code, sym.upcase]
        h[key]   = id
      end

      with_parent    = []
      without_parent = []

      rows.each do |h|
        next without_parent << h if h[:underlying_symbol].blank?

        # h[:instrument_code] is an enum key (e.g., 'futures_index')
        # Convert to CSV code (e.g., 'FUTIDX') for InstrumentTypeMapping
        enum_key = h[:instrument_code].to_s
        csv_code = enum_key_to_csv_code(enum_key)
        parent_code = InstrumentTypeMapping.underlying_for(csv_code)
        key         = [parent_code, h[:underlying_symbol].upcase]

        if (pid = lookup[key])
          h[:instrument_id] = pid
          with_parent << h
        else
          without_parent << h
        end
      end

      [with_parent, without_parent]
    end

    # Convert enum key (e.g., 'futures_index') to CSV code (e.g., 'FUTIDX')
    def enum_key_to_csv_code(enum_key)
      mapping = {
        'index' => 'INDEX',
        'futures_index' => 'FUTIDX',
        'options_index' => 'OPTIDX',
        'equity' => 'EQUITY',
        'futures_stock' => 'FUTSTK',
        'options_stock' => 'OPTSTK',
        'futures_currency' => 'FUTCUR',
        'options_currency' => 'OPTCUR',
        'futures_commodity' => 'FUTCOM',
        'options_commodity' => 'OPTFUT'
      }
      mapping[enum_key.to_s] || enum_key.to_s.upcase
    end

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def safe_date(str)
      Date.parse(str)
    rescue StandardError
      nil
    end

    # Map CSV exchange code to enum key
    def map_exchange(csv_exchange)
      case csv_exchange.to_s.upcase
      when 'NSE' then 'nse'
      when 'BSE' then 'bse'
      when 'MCX' then 'mcx'
      else csv_exchange.to_s.downcase
      end
    end

    # Map CSV segment code to enum key
    def map_segment(csv_segment)
      case csv_segment.to_s.upcase
      when 'I' then 'index'
      when 'E' then 'equity'
      when 'C' then 'currency'
      when 'D' then 'derivatives'
      when 'M' then 'commodity'
      else csv_segment.to_s.downcase
      end
    end

    # Map CSV instrument code (e.g., 'INDEX', 'FUTIDX') to enum key (e.g., 'index', 'futures_index')
    def map_instrument_code_to_enum_key(csv_code)
      mapping = {
        'INDEX' => 'index',
        'FUTIDX' => 'futures_index',
        'OPTIDX' => 'options_index',
        'EQUITY' => 'equity',
        'FUTSTK' => 'futures_stock',
        'OPTSTK' => 'options_stock',
        'FUTCUR' => 'futures_currency',
        'OPTCUR' => 'options_currency',
        'FUTCOM' => 'futures_commodity',
        'OPTFUT' => 'options_commodity'
      }
      mapping[csv_code.to_s.upcase] || csv_code.to_s.downcase
    end

    def record_success!(summary)
      Setting.put('instruments.last_imported_at', summary[:finished_at].iso8601)
      Setting.put('instruments.last_import_duration_sec', summary[:duration].to_f.round(2))
      Setting.put('instruments.last_instrument_rows', summary[:instrument_rows])
      Setting.put('instruments.last_derivative_rows', summary[:derivative_rows])
      Setting.put('instruments.last_instrument_upserts', summary[:instrument_upserts])
      Setting.put('instruments.last_derivative_upserts', summary[:derivative_upserts])
      Setting.put('instruments.instrument_total', summary[:instrument_total])
      Setting.put('instruments.derivative_total', summary[:derivative_total])
    end
  end
end
