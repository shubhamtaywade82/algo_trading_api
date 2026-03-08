# frozen_string_literal: true

require 'csv'

module InstrumentsImport
  # Parses the raw CSV content and builds normalized attribute hashes.
  class Parser < ApplicationService
    VALID_EXCHANGES = %w[NSE BSE MCX].freeze

    def initialize(csv_content)
      @csv_content = csv_content
    end

    def call
      instruments = []
      derivatives = []

      CSV.parse(@csv_content, headers: true).each do |row|
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

      { instruments: instruments, derivatives: derivatives }
    end

    private

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
