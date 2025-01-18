# frozen_string_literal: true

require 'csv'
require 'open-uri'

class InstrumentsImporter
  CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'

  VALID_EXCHANGES = %w[NSE BSE].freeze
  VALID_SEGMENTS = %w[D E I].freeze
  VALID_INSTRUMENTS = %w[OPTIDX FUTIDX OPTSTK FUTSTK EQUITY INDEX].freeze
  VALID_BUY_SELL_INDICATOR = %w[A].freeze # A means both Buy and Sell are allowed

  BATCH_SIZE = 500

  def self.import(file_path = nil)
    file_path ||= download_csv
    Rails.logger.debug { "Using CSV file: #{file_path}" }
    csv_data = filter_csv_data(CSV.read(file_path, headers: true))

    Rails.logger.debug 'Starting CSV import with optimized batch processing...'

    # Step 1: Import Instruments
    instrument_mapping = import_instruments(csv_data)

    # Step 2: Import Derivatives
    import_derivatives(csv_data, instrument_mapping)
    # derivative_mapping = import_derivatives(csv_data, instrument_mapping)

    # NOTE: Skip Margin Requirements and Order features for now
    # # Step 3: Import Margin Requirements
    # import_margin_requirements(csv_data, instrument_mapping, derivative_mapping)

    # # Step 4: Import Order Features
    # import_order_features(csv_data, instrument_mapping, derivative_mapping)

    Rails.logger.debug 'CSV Import completed successfully!'
  end

  def self.download_csv
    Rails.logger.debug { "Downloading CSV from #{CSV_URL}..." }
    tmp_file = Rails.root.join('tmp/api-scrip-master-detailed.csv')
    File.binwrite(tmp_file, URI.open(CSV_URL).read)
    Rails.logger.debug { "CSV downloaded to #{tmp_file}" }
    tmp_file
  end

  def self.filter_csv_data(csv_data)
    Rails.logger.debug 'Filtering CSV data...'
    csv_data.select do |row|
      valid_instrument?(row) || valid_derivative?(row)
    end
  end

  def self.import_instruments(csv_data)
    Rails.logger.debug 'Batch importing instruments...'

    segment_instruments = %w[I E]
    instrument_rows = csv_data.select do |row|
      valid_instrument?(row) && segment_instruments.include?(row['SEGMENT'])
    end.map do |row|
      {
        security_id: row['SECURITY_ID'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        isin: row['ISIN'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        instrument: row['INSTRUMENT'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        lot_size: row['LOT_SIZE'].to_i.positive? ? row['LOT_SIZE'].to_i : nil,
        tick_size: row['TICK_SIZE'].to_f,
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        mtf_leverage: row['MTF_LEVERAGE'].to_f,
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      }
    end

    result = Instrument.import(
      instrument_rows,
      on_duplicate_key_update: {
        conflict_target: %i[security_id symbol_name exchange segment],
        columns: %i[display_name isin instrument underlying_symbol underlying_security_id lot_size tick_size
                    asm_gsm_flag asm_gsm_category mtf_leverage updated_at]
      },
      batch_size: BATCH_SIZE,
      returning: %i[id symbol_name exchange segment]
    )

    Rails.logger.debug { "#{result.ids.size} instruments imported successfully." }

    # Create a mapping of security_id, exchange, and segment to instrument_id
    Instrument.where(security_id: instrument_rows.pluck(:security_id))
              .pluck(:id, :underlying_symbol, :segment, :exchange)
              .each_with_object({}) do |(id, underlying_symbol, segment, exchange), mapping|
      mapping["#{underlying_symbol}-#{Instrument.exchanges[exchange]}"] = id
    end
  end

  def self.import_derivatives(csv_data, instrument_mapping)
    Rails.logger.debug 'Batch importing derivatives...'

    pp instrument_mapping
    derivative_rows = csv_data.select { |row| valid_derivative?(row) && row['SEGMENT'] == 'D' }.filter_map do |row|
      pp "#{row['UNDERLYING_SYMBOL']}-#{row['EXCH_ID']}-#{row['SEGMENT']}"
      instrument_id = instrument_mapping["#{row['UNDERLYING_SYMBOL']}-#{row['EXCH_ID']}"]
      next unless instrument_id

      {
        security_id: row['SECURITY_ID'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        expiry_date: parse_date(row['SM_EXPIRY_DATE']),
        strike_price: row['STRIKE_PRICE'].to_f,
        option_type: row['OPTION_TYPE'],
        lot_size: row['LOT_SIZE'].to_i,
        tick_size: row['TICK_SIZE'].to_f,
        asm_gsm_flag: row['ASM_GSM_FLAG'] == 'Y',
        instrument_id: instrument_id,
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      }
    end

    result = Derivative.import(
      derivative_rows,
      on_duplicate_key_update: {
        conflict_target: %i[security_id symbol_name exchange segment],
        columns: %i[display_name instrument_type underlying_symbol underlying_security_id expiry_date strike_price
                    option_type lot_size tick_size asm_gsm_flag instrument_id updated_at]
      },
      batch_size: BATCH_SIZE,
      returning: %i[id symbol_name exchange segment]
    )

    Rails.logger.debug { "#{result.ids.size} derivatives imported successfully." }

    # Create a mapping of symbol_name, exchange, and segment to derivative_id
    Derivative.where(security_id: derivative_rows.pluck(:security_id))
              .pluck(:id, :symbol_name, :exchange, :segment)
              .each_with_object({}) do |(id, symbol_name, exchange, segment), mapping|
      mapping["#{symbol_name}-#{Instrument.exchanges[exchange]}-#{Instrument.segments[segment]}"] = id
    end
  end

  def self.import_margin_requirements(csv_data, instrument_mapping, derivative_mapping)
    Rails.logger.debug 'Batch importing margin requirements...'

    margin_rows = csv_data.filter_map do |row|
      association_key = "#{row['UNDERLYING_SYMBOL']}-#{row['EXCH_ID']}-#{row['SEGMENT']}"
      requirementable_id, requirementable_type = if instrument_mapping.key?(association_key)
                                                   [instrument_mapping[association_key], 'Instrument']
                                                 elsif derivative_mapping.key?(association_key)
                                                   [derivative_mapping[association_key], 'Derivative']
                                                 end
      next unless requirementable_id

      {
        requirementable_id: requirementable_id,
        requirementable_type: requirementable_type,
        buy_co_min_margin_per: row['BUY_CO_MIN_MARGIN_PER'].to_f,
        sell_co_min_margin_per: row['SELL_CO_MIN_MARGIN_PER'].to_f,
        buy_bo_min_margin_per: row['BUY_BO_MIN_MARGIN_PER'].to_f,
        sell_bo_min_margin_per: row['SELL_BO_MIN_MARGIN_PER'].to_f,
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      }
    end

    MarginRequirement.import(
      margin_rows,
      on_duplicate_key_update: {
        conflict_target: %i[requirementable_id requirementable_type],
        columns: %i[
          buy_co_min_margin_per sell_co_min_margin_per buy_bo_min_margin_per
          sell_bo_min_margin_per updated_at
        ]
      },
      batch_size: BATCH_SIZE
    )

    Rails.logger.debug { "#{margin_rows.size} margin requirements imported successfully." }
  end

  def self.import_order_features(csv_data, instrument_mapping, derivative_mapping)
    Rails.logger.debug 'Batch importing order features...'

    feature_rows = csv_data.filter_map do |row|
      association_key = "#{row['UNDERLYING_SYMBOL']}-#{row['EXCH_ID']}-#{row['SEGMENT']}"
      featureable_id, featureable_type = if instrument_mapping.key?(association_key)
                                           [instrument_mapping[association_key], 'Instrument']
                                         elsif derivative_mapping.key?(association_key)
                                           [derivative_mapping[association_key], 'Derivative']
                                         end
      next unless featureable_id

      {
        featureable_id: featureable_id,
        featureable_type: featureable_type,
        bracket_flag: row['BRACKET_FLAG'],
        cover_flag: row['COVER_FLAG'],
        buy_sell_indicator: row['BUY_SELL_INDICATOR'],
        created_at: Time.zone.now,
        updated_at: Time.zone.now
      }
    end

    OrderFeature.import(
      feature_rows,
      on_duplicate_key_update: {
        conflict_target: %i[featureable_id featureable_type],
        columns: %i[bracket_flag cover_flag buy_sell_indicator updated_at]
      },
      batch_size: BATCH_SIZE
    )

    Rails.logger.debug { "#{feature_rows.size} order features imported successfully." }
  end

  def self.valid_instrument?(row)
    VALID_EXCHANGES.include?(row['EXCH_ID']) && VALID_INSTRUMENTS.include?(row['INSTRUMENT']) && VALID_SEGMENTS.include?(row['SEGMENT'])
  end

  def self.valid_derivative?(row)
    %w[FUTIDX OPTIDX FUTSTK OPTSTK FUTCUR OPTCUR].include?(row['INSTRUMENT']) && VALID_SEGMENTS.include?(row['SEGMENT'])
  end

  def self.parse_date(date_string)
    Date.parse(date_string)
  rescue StandardError
    nil
  end
end
