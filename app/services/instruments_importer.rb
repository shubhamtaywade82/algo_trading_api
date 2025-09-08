# frozen_string_literal: true

require 'csv'
require 'open-uri'

class InstrumentsImporter
  CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'

  VALID_EXCHANGES   = AppSetting.fetch_array('valid_exchanges',   default: %w[NSE BSE MCX]).freeze
  VALID_INSTRUMENTS = AppSetting.fetch_array('valid_instruments', default: %w[OPTIDX FUTIDX OPTSTK FUTSTK FUTCUR OPTCUR FUTCOM OPTFUT EQUITY INDEX]).freeze
  BATCH_SIZE = 500

  def self.import(file_path = nil)
    file_path ||= download_csv
    Rails.logger.debug { "Using CSV file: #{file_path}" }
    csv_data = CSV.read(file_path, headers: true)

    Rails.logger.debug 'Starting CSV import with optimized batch processing...'

    instrument_mapping = import_instruments(csv_data)
    import_derivatives(csv_data, instrument_mapping)

    Rails.logger.debug 'CSV Import completed successfully!'
  end

  def self.download_csv
    Rails.logger.debug { "Downloading CSV from #{CSV_URL}..." }
    tmp_file = Rails.root.join('tmp/api-scrip-master-detailed.csv')
    File.binwrite(tmp_file, URI.open(CSV_URL).read)
    Rails.logger.debug { "CSV downloaded to #{tmp_file}" }
    tmp_file
  end

  def self.import_instruments(csv_data)
    Rails.logger.debug 'Batch importing instruments...'

    instrument_rows = csv_data.select do |row|
      valid_instrument?(row)
    end.filter_map do |row|
      next if row['SEGMENT'] == 'D' # Derivatives handled separately

      {
        security_id: row['SECURITY_ID'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        isin: row['ISIN'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        instrument: row['INSTRUMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        series: row['SERIES'],
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

    Instrument.where(security_id: instrument_rows.pluck(:security_id))
              .pluck(:id, :underlying_symbol, :segment, :exchange)
              .each_with_object({}) do |(id, underlying_symbol, _segment, exchange), mapping|
      mapping["#{underlying_symbol}-#{Instrument.exchanges[exchange]}"] = id
    end
  end

  def self.import_derivatives(csv_data, instrument_mapping)
    Rails.logger.debug 'Batch importing derivatives...'
    derivative_rows = csv_data.select do |row|
      valid_derivative?(row) && row['SEGMENT'] == 'D'
    end.filter_map do |row|
      instrument_id = instrument_mapping["#{row['UNDERLYING_SYMBOL']}-#{row['EXCH_ID']}"]
      next unless instrument_id

      {
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT'],
        security_id: row['SECURITY_ID'],
        symbol_name: row['SYMBOL_NAME'],
        display_name: row['DISPLAY_NAME'],
        instrument: row['INSTRUMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERLYING_SECURITY_ID'],
        expiry_date: parse_date(row['SM_EXPIRY_DATE']),
        strike_price: row['STRIKE_PRICE'].to_f,
        option_type: row['OPTION_TYPE'],
        expiry_flag: row['EXPIRY_FLAG'],
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
  end

  def self.valid_instrument?(row)
    VALID_EXCHANGES.include?(row['EXCH_ID']) &&
      VALID_INSTRUMENTS.include?(row['INSTRUMENT'])
  end

  def self.valid_derivative?(row)
    %w[FUTIDX OPTIDX FUTSTK OPTSTK FUTCUR OPTCUR FUTCOM OPTFUT].include?(row['INSTRUMENT'])
  end

  def self.parse_date(date_string)
    Date.parse(date_string)
  rescue StandardError
    nil
  end
end
