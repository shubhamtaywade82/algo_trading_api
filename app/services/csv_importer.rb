require "csv"

class CsvImporter
  VALID_EXCHANGES = %w[NSE BSE].freeze
  VALID_SEGMENTS = %w[C D E I].freeze
  VALID_INSTRUMENT_TYPES = %w[FUTCUR OPTCUR OPTIDX FUTIDX OPTSTK FUTSTK EQUITY INDEX].freeze

  def self.import(file_path)
    csv_data = CSV.read(file_path, headers: true)

    # Import Exchanges
    import_exchanges(csv_data)

    # Import Segments
    import_segments(csv_data)

    # Import Instruments
    import_instruments(csv_data)

    # Import Derivatives
    import_derivatives(csv_data)

    # Import Margin Requirements
    import_margin_requirements(csv_data)

    # Import Order Features
    import_order_features(csv_data)

    puts "CSV Import completed successfully!"
  end

  private

  def self.import_exchanges(csv_data)
    return if Exchange.count == 3

    puts "Importing Exchanges..."

    unique_exchanges = csv_data.map { |row| row["EXCH_ID"] }.uniq.compact

    unique_exchanges.each do |exch_id|
      Exchange.find_or_create_by(exch_id: exch_id) do |exchange|
        exchange.name = DhanhqMappings::EXCHANGES[exch_id]
      end
    end
    puts "Imported Exchanges: #{unique_exchanges.join(', ')}"
  end

  def self.import_segments(csv_data)
    return if Segment.count == 5
    puts "Importing Segments..."

    unique_segments = csv_data.map { |row| row["SEGMENT"] }.uniq.compact
    unique_segments.each do |segment_code|
      Segment.find_or_create_by(segment_code: segment_code) do |segment|
        segment.description = DhanhqMappings::SEGMENTS[segment_code]
      end
    end
    puts "Imported Segments: #{unique_segments.join(', ')}"
  end

  def self.import_instruments(csv_data)
    puts "Importing Instruments..."
    csv_data.each do |row|
      next unless valid_instrument?(row)

      exchange = Exchange.find_by(exch_id: row["EXCH_ID"])
      segment = Segment.find_by(segment_code: row["SEGMENT"])

      next unless exchange && segment

      pp row

      Instrument.find_or_create_by(security_id: row["SECURITY_ID"]) do |instrument|
        instrument.isin = row["ISIN"]
        instrument.instrument = row["INSTRUMENT"]
        instrument.underlying_symbol = row["UNDERLYING_SYMBOL"]
        instrument.symbol_name = row["SYMBOL_NAME"]
        instrument.display_name = row["DISPLAY_NAME"]
        instrument.instrument_type = row["INSTRUMENT_TYPE"]
        instrument.series = row["SERIES"]
        instrument.lot_size = row["LOT_SIZE"].to_i.positive? ? row["LOT_SIZE"].to_i : nil
        instrument.tick_size = row["TICK_SIZE"]
        instrument.asm_gsm_flag = row["ASM_GSM_FLAG"]
        instrument.asm_gsm_category = row["ASM_GSM_CATEGORY"]
        instrument.mtf_leverage = row["MTF_LEVERAGE"]
        instrument.exchange = exchange
        instrument.segment = segment
      end

      pp "Imported Instrument: #{row['SYMBOL_NAME']}"
    end
  end

  def self.import_derivatives(csv_data)
    puts "Importing Derivatives..."
    csv_data.each do |row|
      next unless row["STRIKE_PRICE"] || row["OPTION_TYPE"]

      instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next unless instrument

      Derivative.find_or_create_by(instrument: instrument, strike_price: row["STRIKE_PRICE"]) do |derivative|
        derivative.option_type = row["OPTION_TYPE"]
        derivative.expiry_date = row["SM_EXPIRY_DATE"]
        derivative.expiry_flag = row["EXPIRY_FLAG"]
      end
    end
  end

  def self.import_margin_requirements(csv_data)
    puts "Importing Margin Requirements..."
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next unless instrument

      MarginRequirement.find_or_create_by(instrument: instrument) do |margin|
        margin.buy_co_min_margin_per = row["BUY_CO_MIN_MARGIN_PER"]
        margin.sell_co_min_margin_per = row["SELL_CO_MIN_MARGIN_PER"]
        margin.buy_bo_min_margin_per = row["BUY_BO_MIN_MARGIN_PER"]
        margin.sell_bo_min_margin_per = row["SELL_BO_MIN_MARGIN_PER"]
        margin.buy_co_sl_range_max_perc = row["BUY_CO_SL_RANGE_MAX_PERC"]
        margin.sell_co_sl_range_max_perc = row["SELL_CO_SL_RANGE_MAX_PERC"]
        margin.buy_co_sl_range_min_perc = row["BUY_CO_SL_RANGE_MIN_PERC"]
        margin.sell_co_sl_range_min_perc = row["SELL_CO_SL_RANGE_MIN_PERC"]
        margin.buy_bo_sl_range_max_perc = row["BUY_BO_SL_RANGE_MAX_PERC"]
        margin.sell_bo_sl_range_max_perc = row["SELL_BO_SL_RANGE_MAX_PERC"]
        margin.buy_bo_sl_range_min_perc = row["BUY_BO_SL_RANGE_MIN_PERC"]
        margin.sell_bo_sl_min_range = row["SELL_BO_SL_MIN_RANGE"]
        margin.buy_bo_profit_range_max_perc = row["BUY_BO_PROFIT_RANGE_MAX_PERC"]
        margin.sell_bo_profit_range_max_perc = row["SELL_BO_PROFIT_RANGE_MAX_PERC"]
        margin.buy_bo_profit_range_min_perc = row["BUY_BO_PROFIT_RANGE_MIN_PERC"]
        margin.sell_bo_profit_range_min_perc = row["SELL_BO_PROFIT_RANGE_MIN_PERC"]
      end
    end
  end

  def self.import_order_features(csv_data)
    puts "Importing Order Features..."
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next unless instrument

      OrderFeature.find_or_create_by(instrument: instrument) do |feature|
        feature.bracket_flag = row["BRACKET_FLAG"]
        feature.cover_flag = row["COVER_FLAG"]
        feature.buy_sell_indicator = row["BUY_SELL_INDICATOR"]
      end
    end
  end

  def self.valid_instrument?(row)
    VALID_INSTRUMENT_TYPES.include?(row["INSTRUMENT_TYPE"]) && row["LOT_SIZE"].to_i.positive?
  end
end
