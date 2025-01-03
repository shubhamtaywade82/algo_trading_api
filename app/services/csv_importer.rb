require "csv"
require "open-uri"

class CsvImporter
  CSV_URL = "https://images.dhan.co/api-data/api-scrip-master-detailed.csv".freeze
  VALID_EXCHANGES = %w[NSE BSE].freeze
  VALID_SEGMENTS = %w[C D E I].freeze
  VALID_INSTRUMENTS = %w[FUTCUR OPTCUR OPTIDX FUTIDX OPTSTK FUTSTK EQUITY INDEX].freeze
  VALID_BUY_SELL_INDICATOR = %w[A].freeze # A means both Buy and Sell are allowed

  def self.import
    file_path = download_csv
    csv_data = filter_csv_data(CSV.read(file_path, headers: true))

    # Import Exchanges
    import_exchanges(csv_data)

    # Import Segments
    import_segments(csv_data)

    # Import Exchange Segments
    import_exchange_segments(csv_data)

    # Import Instruments
    # import_instruments(csv_data)

    # Import Derivatives
    import_derivatives(csv_data)

    # Import Margin Requirements
    import_margin_requirements(csv_data)

    # Import Order Features
    import_order_features(csv_data)

    # Cleanup temporary file
    File.delete(file_path) if File.exist?(file_path)

    puts "CSV Import completed successfully!"
  end

  private

  def self.download_csv
    puts "Downloading CSV from #{CSV_URL}..."
    tmp_file = Rails.root.join("tmp", "api-scrip-master-detailed.csv")
    File.open(tmp_file, "wb") do |file|
      file.write(URI.open(CSV_URL).read)
    end
    puts "CSV downloaded to #{tmp_file}"
    tmp_file
  end

  def self.filter_csv_data(csv_data)
    puts "Filtering CSV data..."
    csv_data.select do |row|
      valid_instrument?(row) && valid_buy_sell_indicator?(row) && valid_expiry_date?(row)
    end
  end

  def self.import_exchanges(csv_data)
    puts "Importing Exchanges..."
    unique_exchanges = csv_data.map { |row| row["EXCH_ID"] }.uniq.compact
    unique_exchanges.each do |exch_id|
      Exchange.find_or_create_by!(exch_id: exch_id) do |exchange|
        exchange.name = DhanhqMappings::EXCHANGES[exch_id]
      end
    end
    puts "Imported Exchanges: #{unique_exchanges.join(', ')}"
  end

  def self.import_segments(csv_data)
    puts "Importing Segments..."
    unique_segments = csv_data.map { |row| row["SEGMENT"] }.uniq.compact
    unique_segments.each do |segment_code|
      Segment.find_or_create_by!(segment_code: segment_code) do |segment|
        segment.description = DhanhqMappings::SEGMENTS[segment_code.to_sym]
      end
    end
    puts "Imported Segments: #{unique_segments.join(', ')}"
  end

  def self.import_exchange_segments(csv_data)
    puts "Importing Exchange Segments..."

    # Find unique combinations of exchanges and segments
    unique_combinations = csv_data.map { |row| [ row["EXCH_ID"], row["SEGMENT"] ] }.uniq.compact

    unique_combinations.each do |exch_id, segment_code|
      exchange = Exchange.find_by(exch_id: exch_id)
      segment = Segment.find_by(segment_code: segment_code)

      next unless exchange && segment

      exchange_segment_code = derive_exchange_segment(exch_id, segment_code)
      next unless exchange_segment_code

      ExchangeSegment.find_or_create_by!(exchange: exchange, segment: segment) do |exchange_segment|
        exchange_segment.exchange_segment = exchange_segment_code
      end
    end

    puts "Imported Exchange Segments: #{unique_combinations.map { |c| derive_exchange_segment(c[0], c[1]) }.compact.join(', ')}"
  end

  def self.import_instruments(csv_data)
    puts "Importing Instruments..."
    csv_data.each do |row|
      next if Instrument.find_by(security_id: row["SECURITY_ID"], symbol_name: row["SYMBOL_NAME"])
      exchange_segment_code = derive_exchange_segment(row["EXCH_ID"], row["SEGMENT"])
      exchange_segment = ExchangeSegment.find_by(exchange_segment: exchange_segment_code)

      exchange = Exchange.find_by(exch_id: row["EXCH_ID"])
      segment = Segment.find_by(segment_code: row["SEGMENT"])

      next unless exchange && segment

      puts "Importing Instrument: #{row["DISPLAY_NAME"]} (#{row["INSTRUMENT"]})"

      instrument = Instrument.find_or_initialize_by(security_id: row["SECURITY_ID"])
      instrument.update!(
        isin: row["ISIN"],
        instrument: row["INSTRUMENT"],
        underlying_symbol: row["UNDERLYING_SYMBOL"],
        symbol_name: row["SYMBOL_NAME"],
        display_name: row["DISPLAY_NAME"],
        instrument_type: row["INSTRUMENT_TYPE"],
        series: row["SERIES"],
        lot_size: row["LOT_SIZE"].to_i.positive? ? row["LOT_SIZE"].to_i : nil,
        tick_size: row["TICK_SIZE"],
        asm_gsm_flag: row["ASM_GSM_FLAG"],
        asm_gsm_category: row["ASM_GSM_CATEGORY"],
        mtf_leverage: row["MTF_LEVERAGE"],
        exchange: exchange,
        segment: segment,
        exchange_segment: exchange_segment
      )
    end
  end

  def self.import_derivatives(csv_data)
    puts "Importing Derivatives..."
    csv_data.each do |row|
      next unless row["STRIKE_PRICE"] && row["OPTION_TYPE"]

      puts "Importing Derivatives: #{row["DISPLAY_NAME"]} (#{row["INSTRUMENT"]}) #{row["STRIKE_PRICE"]}  #{row["OPTION_TYPE"]} "
      expiry_date = parse_date(row["SM_EXPIRY_DATE"])
      next unless expiry_date && expiry_date >= Date.today # Only upcoming expiries

      instrument = Instrument.find_by(security_id: row["SECURITY_ID"], underlying_symbol: row["UNDERLYING_SYMBOL"])
      next unless instrument

      derivative = Derivative.find_or_initialize_by(
        instrument: instrument,
        strike_price: row["STRIKE_PRICE"],
        option_type: row["OPTION_TYPE"],
        expiry_date: expiry_date
      )
      derivative.update!(expiry_flag: row["EXPIRY_FLAG"])
    end
  end

  def self.import_margin_requirements(csv_data)
    puts "Importing Margin Requirements..."
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next unless instrument

      margin = MarginRequirement.find_or_initialize_by(instrument: instrument)
      margin.update!(
        buy_co_min_margin_per: row["BUY_CO_MIN_MARGIN_PER"],
        sell_co_min_margin_per: row["SELL_CO_MIN_MARGIN_PER"],
        buy_bo_min_margin_per: row["BUY_BO_MIN_MARGIN_PER"],
        sell_bo_min_margin_per: row["SELL_BO_MIN_MARGIN_PER"],
        buy_co_sl_range_max_perc: row["BUY_CO_SL_RANGE_MAX_PERC"],
        sell_co_sl_range_max_perc: row["SELL_CO_SL_RANGE_MAX_PERC"],
        buy_co_sl_range_min_perc: row["BUY_CO_SL_RANGE_MIN_PERC"],
        sell_co_sl_range_min_perc: row["SELL_CO_SL_RANGE_MIN_PERC"],
        buy_bo_sl_range_max_perc: row["BUY_BO_SL_RANGE_MAX_PERC"],
        sell_bo_sl_range_max_perc: row["SELL_BO_SL_RANGE_MAX_PERC"],
        buy_bo_sl_range_min_perc: row["BUY_BO_SL_RANGE_MIN_PERC"],
        sell_bo_sl_min_range: row["SELL_BO_SL_MIN_RANGE"],
        buy_bo_profit_range_max_perc: row["BUY_BO_PROFIT_RANGE_MAX_PERC"],
        sell_bo_profit_range_max_perc: row["SELL_BO_PROFIT_RANGE_MAX_PERC"],
        buy_bo_profit_range_min_perc: row["BUY_BO_PROFIT_RANGE_MIN_PERC"],
        sell_bo_profit_range_min_perc: row["SELL_BO_PROFIT_RANGE_MIN_PERC"]
      )
    end
  end

  def self.import_order_features(csv_data)
    puts "Importing Order Features..."
    csv_data.each do |row|
      instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next unless instrument

      feature = OrderFeature.find_or_initialize_by(instrument: instrument)
      feature.update!(
        bracket_flag: row["BRACKET_FLAG"],
        cover_flag: row["COVER_FLAG"],
        buy_sell_indicator: row["BUY_SELL_INDICATOR"]
      )
    end
  end

  def self.derive_exchange_segment(exch_id, segment_code)
    {
      [ "NSE", "I" ] => "IDX_I",
      %w[BSE I] => "IDX_I",
      [ "NSE", "E" ] => "NSE_EQ",
      [ "BSE", "E" ] => "BSE_EQ",
      [ "NSE", "D" ] => "NSE_FNO",
      [ "BSE", "D" ] => "BSE_FNO",
      [ "NSE", "C" ] => "NSE_CURRENCY",
      [ "BSE", "C" ] => "BSE_CURRENCY",
      [ "MCX", "M" ] => "MCX_COMM"
    }[[ exch_id, segment_code ]]
  end

  def self.valid_instrument?(row)
    VALID_INSTRUMENTS.include?(row["INSTRUMENT"]) && row["LOT_SIZE"].to_i.positive?
  end

  def self.valid_buy_sell_indicator?(row)
    VALID_BUY_SELL_INDICATOR.include?(row["BUY_SELL_INDICATOR"])
  end

  def self.valid_expiry_date?(row)
    return true unless row["SM_EXPIRY_DATE"]

    expiry_date = parse_date(row["SM_EXPIRY_DATE"])
    expiry_date.nil? || expiry_date >= Date.today || expiry_date == parse_date("1979-12-31")
  end

  def self.parse_date(date_string)
    Date.parse(date_string) rescue nil
  end
end
