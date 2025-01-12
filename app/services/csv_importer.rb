# frozen_string_literal: true

require 'csv'
require 'open-uri'

class CsvImporter
  CSV_URL = 'https://images.dhan.co/api-data/api-scrip-master-detailed.csv'

  VALID_EXCHANGES = %w[NSE BSE].freeze
  VALID_SEGMENTS = %w[D E I].freeze
  VALID_INSTRUMENTS = %w[OPTIDX FUTIDX OPTSTK FUTSTK EQUITY INDEX].freeze
  VALID_BUY_SELL_INDICATOR = %w[A].freeze # A means both Buy and Sell are allowed

  def self.import
    file_path = download_csv
    csv_data = filter_csv_data(CSV.read(file_path, headers: true))

    # Import Instruments
    import_instruments(csv_data)

    # Import Derivatives
    import_derivatives(csv_data)

    # Import Margin Requirements
    import_margin_requirements(csv_data)

    # Import Order Features
    import_order_features(csv_data)

    # Cleanup temporary file
    # File.delete(file_path) if File.exist?(file_path)

    Rails.logger.debug 'CSV Import completed successfully!'
  end

  def self.import_csv_data(file_path)
    Rails.logger.debug 'Importing filtered CSV data...'
    csv_data = filter_csv_data(CSV.read(file_path, headers: true))
    # Import Instruments
    import_instruments(csv_data)

    # Import Derivatives
    import_derivatives(csv_data)

    # Import Margin Requirements
    import_margin_requirements(csv_data)

    # Import Order Features
    import_order_features(csv_data)

    Rails.logger.debug 'Filtered CSV Import completed successfully!'
    pp Instrument.count
    pp Instrument.select(:segment).distinct
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
      valid_instrument?(row) && valid_buy_sell_indicator?(row) && valid_expiry_date?(row)
    end
  end

  def self.import_instruments(csv_data)
    Rails.logger.debug 'Importing Instruments...'
    csv_data.each do |row|
      next if Instrument.find_by(security_id: row['SECURITY_ID'], symbol_name: row['SYMBOL_NAME'])

      Rails.logger.debug { "Importing Instrument: #{row['DISPLAY_NAME']} (#{row['INSTRUMENT']})" }

      instrument = Instrument.find_or_initialize_by(security_id: row['SECURITY_ID'], symbol_name: row['SYMBOL_NAME'])
      next unless instrument

      instrument.update(
        isin: row['ISIN'],
        instrument: row['INSTRUMENT'],
        instrument_type: row['INSTRUMENT_TYPE'],
        underlying_symbol: row['UNDERLYING_SYMBOL'],
        underlying_security_id: row['UNDERYLING_SECURITY_ID'],
        display_name: row['DISPLAY_NAME'],
        series: row['SERIES'],
        lot_size: row['LOT_SIZE'].to_i.positive? ? row['LOT_SIZE'].to_i : nil,
        tick_size: row['TICK_SIZE'],
        asm_gsm_flag: row['ASM_GSM_FLAG'],
        asm_gsm_category: row['ASM_GSM_CATEGORY'],
        mtf_leverage: row['MTF_LEVERAGE'],
        exchange: row['EXCH_ID'],
        segment: row['SEGMENT']
      )
    end
  end

  def self.import_derivatives(csv_data)
    Rails.logger.debug 'Importing Derivatives...'
    csv_data.each do |row|
      next unless row['STRIKE_PRICE'] && row['OPTION_TYPE']

      Rails.logger.debug do
        "Importing Derivatives: #{row['DISPLAY_NAME']} (#{row['INSTRUMENT']}) #{row['STRIKE_PRICE']} #{row['OPTION_TYPE']}"
      end
      expiry_date = parse_date(row['SM_EXPIRY_DATE'])
      next unless expiry_date && expiry_date >= Time.zone.today # Only upcoming expiries

      instrument = Instrument.find_by(security_id: row['SECURITY_ID'], underlying_symbol: row['UNDERLYING_SYMBOL'])
      next unless instrument

      derivative = Derivative.find_or_initialize_by(
        instrument: instrument,
        strike_price: row['STRIKE_PRICE'],
        option_type: row['OPTION_TYPE'],
        expiry_date: expiry_date
      )
      derivative.update!(expiry_flag: row['EXPIRY_FLAG'])
    end
  end

  def self.import_margin_requirements(csv_data)
    Rails.logger.debug 'Importing Margin Requirements...'
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row['SECURITY_ID'])
      next unless instrument

      margin = MarginRequirement.find_or_initialize_by(instrument: instrument)
      margin.update!(
        buy_co_min_margin_per: row['BUY_CO_MIN_MARGIN_PER'],
        sell_co_min_margin_per: row['SELL_CO_MIN_MARGIN_PER'],
        buy_bo_min_margin_per: row['BUY_BO_MIN_MARGIN_PER'],
        sell_bo_min_margin_per: row['SELL_BO_MIN_MARGIN_PER'],
        buy_co_sl_range_max_perc: row['BUY_CO_SL_RANGE_MAX_PERC'],
        sell_co_sl_range_max_perc: row['SELL_CO_SL_RANGE_MAX_PERC'],
        buy_co_sl_range_min_perc: row['BUY_CO_SL_RANGE_MIN_PERC'],
        sell_co_sl_range_min_perc: row['SELL_CO_SL_RANGE_MIN_PERC'],
        buy_bo_sl_range_max_perc: row['BUY_BO_SL_RANGE_MAX_PERC'],
        sell_bo_sl_range_max_perc: row['SELL_BO_SL_RANGE_MAX_PERC'],
        buy_bo_sl_range_min_perc: row['BUY_BO_SL_RANGE_MIN_PERC'],
        sell_bo_sl_min_range: row['SELL_BO_SL_MIN_RANGE'],
        buy_bo_profit_range_max_perc: row['BUY_BO_PROFIT_RANGE_MAX_PERC'],
        sell_bo_profit_range_max_perc: row['SELL_BO_PROFIT_RANGE_MAX_PERC'],
        buy_bo_profit_range_min_perc: row['BUY_BO_PROFIT_RANGE_MIN_PERC'],
        sell_bo_profit_range_min_perc: row['SELL_BO_PROFIT_RANGE_MIN_PERC']
      )
    end
  end

  def self.import_order_features(csv_data)
    Rails.logger.debug 'Importing Order Features...'
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row['SECURITY_ID'])
      next unless instrument

      feature = OrderFeature.find_or_initialize_by(instrument: instrument)
      feature.update!(
        bracket_flag: row['BRACKET_FLAG'],
        cover_flag: row['COVER_FLAG'],
        buy_sell_indicator: row['BUY_SELL_INDICATOR']
      )
    end
  end

  def self.valid_instrument?(row)
    VALID_EXCHANGES.include?(row['EXCH_ID']) && VALID_INSTRUMENTS.include?(row['INSTRUMENT']) && row['LOT_SIZE'].to_i.positive? && VALID_SEGMENTS.include?(row['SEGMENT'])
  end

  def self.valid_buy_sell_indicator?(row)
    VALID_BUY_SELL_INDICATOR.include?(row['BUY_SELL_INDICATOR'])
  end

  def self.valid_expiry_date?(row)
    return true unless row['SM_EXPIRY_DATE']

    expiry_date = parse_date(row['SM_EXPIRY_DATE'])
    expiry_date.nil? || expiry_date >= Time.zone.today
  end

  def self.parse_date(date_string)
    Date.parse(date_string)
  rescue StandardError
    nil
  end
end
