# frozen_string_literal: true

require 'csv'
require 'open-uri'

# Imports Dhan API scrip master CSV into instruments and derivatives.
# Implementation follows algo_scalper_api app/services/instruments_importer.rb:
# import_from_url / import_from_csv, fetch_csv_with_cache, build_batches,
# attach_instrument_ids via InstrumentTypeMapping.underlying_for.
# This app keeps column name "instrument" (not instrument_code) and existing schema.
class InstrumentsImporter
  CSV_URL       = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'
  CACHE_PATH    = Rails.root.join('tmp/dhan_scrip_master.csv')
  CACHE_MAX_AGE = 24.hours
  VALID_EXCHANGES = %w[NSE BSE MCX].freeze
  BATCH_SIZE = 1_000

  class << self
    def import_from_url
      started_at = Time.current
      csv_text   = fetch_csv_with_cache
      summary    = import_from_csv(csv_text)
      summary[:started_at]  = started_at
      summary[:finished_at] = Time.current
      summary[:duration] = summary[:finished_at] - started_at
      record_success!(summary)
      summary
    end

    def fetch_csv_with_cache
      return CACHE_PATH.read if CACHE_PATH.exist? && (Time.current - CACHE_PATH.mtime) < CACHE_MAX_AGE

      csv_text = URI.open(CSV_URL, &:read)
      CACHE_PATH.dirname.mkpath
      File.write(CACHE_PATH, csv_text)
      csv_text
    rescue StandardError => e
      raise e unless CACHE_PATH.exist?

      CACHE_PATH.read
    end

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

    # Backward compatibility: import(nil) = import_from_url; import(path) = read file and import_from_csv (no record_success).
    def import(file_path = nil)
      started = Time.current
      csv_content = file_path ? File.read(file_path) : fetch_csv_with_cache
      summary = import_from_csv(csv_content)
      if file_path.nil?
        summary[:finished_at] = Time.current
        summary[:duration] = summary[:finished_at] - started
        record_success!(summary)
      end
      summary
    end

    private

    def build_batches(csv_content)
      instruments = []
      derivatives = []
      CSV.parse(csv_content, headers: true).each do |row|
        next unless VALID_EXCHANGES.include?(row['EXCH_ID'])

        attrs = build_attrs(row)
        if row['SEGMENT'] == 'D'
          dr = attrs.slice(*derivative_column_symbols)
          dr[:asm_gsm_flag] = (row['ASM_GSM_FLAG'] == 'Y') if dr.key?(:asm_gsm_flag)
          derivatives << dr
        else
          instruments << attrs.slice(*instrument_column_symbols)
        end
      end
      [instruments, derivatives]
    end

    def instrument_column_symbols
      @instrument_column_symbols ||= (Instrument.column_names - ['id']).map(&:to_sym).freeze
    end

    def derivative_column_symbols
      @derivative_column_symbols ||= (Derivative.column_names - ['id']).map(&:to_sym).freeze
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
        instrument: row['INSTRUMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        series: row['SERIES'],
        lot_size: lot_size,
        tick_size: safe_float(row['TICK_SIZE']),
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        mtf_leverage: safe_float(row['MTF_LEVERAGE']),
        expiry_date: safe_date(row['SM_EXPIRY_DATE']),
        strike_price: safe_float(row['STRIKE_PRICE']),
        option_type: row['OPTION_TYPE'],
        expiry_flag: row['EXPIRY_FLAG'],
        created_at: now,
        updated_at: now
      }
    end

    def import_instruments!(rows)
      Instrument.import(
        rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[display_name isin instrument instrument_type underlying_symbol series lot_size tick_size asm_gsm_flag
                      asm_gsm_category mtf_leverage updated_at]
        }
      )
    end

    def import_derivatives!(rows)
      with_parent, = attach_instrument_ids(rows)
      return if with_parent.empty?

      valid_ids = Instrument.where(id: with_parent.filter_map { |r| r[:instrument_id] }.uniq).pluck(:id).to_set
      validated = with_parent.select { |r| r[:instrument_id] && valid_ids.include?(r[:instrument_id]) }
      return if validated.empty?

      Derivative.import(
        validated,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: %i[display_name isin instrument instrument_type underlying_symbol underlying_security_id series expiry_date strike_price
                      option_type lot_size expiry_flag tick_size asm_gsm_flag instrument_id updated_at]
        }
      )
    end

    def attach_instrument_ids(rows)
      lookup = Instrument.pluck(:id, :instrument, :underlying_symbol).each_with_object({}) do |(id, inst, sym), h|
        next if sym.blank?

        key = [inst.to_s.strip.upcase, sym.to_s.strip.upcase]
        h[key] = id
      end
      with_parent = []
      without_parent = []
      rows.each do |h|
        sym = h[:underlying_symbol].to_s.strip.upcase
        if sym.blank?
          without_parent << h
          next
        end
        parent_code = InstrumentTypeMapping.underlying_for(h[:instrument])
        key = [parent_code.to_s.upcase, sym]
        if (pid = lookup[key])
          h[:instrument_id] = pid
          with_parent << h
        else
          without_parent << h
        end
      end
      [with_parent, without_parent]
    end

    def safe_date(str)
      Date.parse(str.to_s)
    rescue StandardError
      nil
    end

    def safe_float(val)
      val.to_s.strip.empty? ? nil : val.to_f
    end

    def record_success!(summary)
      return unless defined?(AppSetting) && AppSetting.respond_to?(:[]=)

      write_setting('instruments.last_imported_at', summary[:finished_at]&.iso8601)
      write_setting('instruments.last_import_duration_sec', summary[:duration]&.then { |d| d.to_f.round(2).to_s })
      write_setting('instruments.last_instrument_rows', summary[:instrument_rows].to_s)
      write_setting('instruments.last_derivative_rows', summary[:derivative_rows].to_s)
      write_setting('instruments.last_instrument_upserts', summary[:instrument_upserts].to_s)
      write_setting('instruments.last_derivative_upserts', summary[:derivative_upserts].to_s)
      write_setting('instruments.instrument_total', summary[:instrument_total].to_s)
      write_setting('instruments.derivative_total', summary[:derivative_total].to_s)
    end

    def write_setting(key, value)
      return if value.blank?

      AppSetting[key] = value
    end
  end
end
