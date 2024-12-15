require "csv"
require "open-uri"

class InstrumentSyncService
  DETAILED_CSV_URL = "https://images.dhan.co/api-data/api-scrip-master-detailed.csv"

  def self.sync_instruments
    csv_file = download_csv

    CSV.foreach(csv_file.path, headers: true) do |row|
      expiry_date = parse_date(row["SM_EXPIRY_DATE"])
      next if expiry_date && expiry_date < Date.today

      # Check if the instrument already exists
      existing_instrument = Instrument.find_by(security_id: row["SECURITY_ID"])
      next if existing_instrument # Skip if the instrument is already present

      # Create or update the instrument
      Instrument.find_or_initialize_by(security_id: row["SECURITY_ID"]).tap do |instrument|
        instrument.exch_id = row["EXCH_ID"]
        instrument.segment = row["SEGMENT"]
        instrument.isin = row["ISIN"]
        instrument.instrument = row["INSTRUMENT"]
        instrument.underlying_symbol = row["UNDERLYING_SYMBOL"]
        instrument.symbol_name = row["SYMBOL_NAME"]
        instrument.display_name = row["DISPLAY_NAME"]
        instrument.instrument_type = row["INSTRUMENT_TYPE"]
        instrument.lot_size = row["LOT_SIZE"].to_i
        instrument.sm_expiry_date = expiry_date
        instrument.strike_price = row["STRIKE_PRICE"].to_f
        instrument.option_type = row["OPTION_TYPE"]
        instrument.tick_size = row["TICK_SIZE"].to_f
        instrument.expiry_flag = row["EXPIRY_FLAG"] != "NA" ? row["EXPIRY_FLAG"] : nil
        instrument.asm_gsm_flag = row["ASM_GSM_FLAG"]
        instrument.buy_co_min_margin_per = row["BUY_CO_MIN_MARGIN_PER"].to_f
        instrument.sell_co_min_margin_per = row["SELL_CO_MIN_MARGIN_PER"].to_f
        instrument.buy_bo_min_margin_per = row["BUY_BO_MIN_MARGIN_PER"].to_f
        instrument.sell_bo_min_margin_per = row["SELL_BO_MIN_MARGIN_PER"].to_f
        instrument.mtf_leverage = row["MTF_LEVERAGE"].to_f

        instrument.save!
      end
    end
  ensure
    csv_file.close
    csv_file.unlink
  end

  private

  def self.download_csv
    tmp_file = Tempfile.new("api-scrip-master-detailed.csv")
    URI.open(DETAILED_CSV_URL) do |data|
      tmp_file.write(data.read)
    end
    tmp_file.rewind
    tmp_file
  end

  def self.parse_date(date_string)
    Date.parse(date_string) rescue nil
  end
end
