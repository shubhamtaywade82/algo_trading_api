class Instrument < ApplicationRecord
  # Define the enum for instrument_type with string mapping
  enum :instrument_type, {
    "FUTCUR" => "FUTCUR",
    "OPTCUR" => "OPTCUR",
    "OPTIDX" => "OPTIDX",
    "FUTIDX" => "FUTIDX",
    "OPTSTK" => "OPTSTK",
    "FUTSTK" => "FUTSTK",
    "ES" => "ES",
    "Other" => "Other",
    "ETF" => "ETF",
    "MF" => "MF",
    "InvITU" => "InvITU",
    "REIT" => "REIT",
    "EQ" => "EQ",
    "PS" => "PS",
    "CB" => "CB",
    "DBT" => "DBT",
    "DEB" => "DEB",
    "TB" => "TB",
    "GB" => "GB",
    "PN" => "PN",
    "PTC" => "PTC",
    "INDEX" => "INDEX",
    "IDX" => "IDX",
    "FUTCOM" => "FUTCOM",
    "OPTFUT" => "OPTFUT",
    "CUR OP" => "CUR OP",
    "FUT" => "FUT",
    "OP" => "OP"
  }, prefix: :instrument_type

  # Define the enum for segment with string mapping
  enum :segment, {
    "C" => "C",  # Currency
    "D" => "D",  # Derivative
    "E" => "E",  # Equity
    "I" => "I",  # Index
    "M" => "M"   # Commodity
  }, prefix: :segment

  # Define expiry_flag without prefix
  enum :expiry_flag, {
    "1" => "1",  # Immediate
    "H" => "H",  # Half Yearly
    "M" => "M",  # Monthly
    "Q" => "Q",  # Quarterly
    "W" => "W"   # Weekly
  }, prefix: true

  has_one :mis_detail, dependent: :destroy

  # Validation
  validates :instrument_type, inclusion: { in: Instrument.instrument_types.keys }
  validates :segment, inclusion: { in: Instrument.segments.keys }

  # Scopes
  scope :equities, -> { where(instrument_type: "EQ") }
  scope :indices, -> { where(instrument_type: "INDEX") }
  scope :currencies, -> { where(segment: "C") }
  scope :expiring_soon, -> { where(expiry_flag: "1") }

  # Instance Methods
  def display_name
    "#{name} (#{instrument_type})"
  end

  def full_segment_name
    case segment
    when "C" then "Currency"
    when "D" then "Derivative"
    when "E" then "Equity"
    when "I" then "Index"
    when "M" then "Commodity"
    else "Unknown"
    end
  end

  def ltp
    # Dynamically derive the exchange segment
    exchange_segment = self.exchange_segment
    return nil if exchange_segment == "UNKNOWN"

    # Call the API using the derived segment and security ID
    response = Dhanhq::API::MarketFeed.ltp({ exchange_segment => [ security_id.to_i ] })

    # Check the response status and return the LTP or log an error
    if response["status"] == "success"
      response.dig("data", exchange_segment, security_id.to_s, "last_price")
    else
      Rails.logger.error("Failed to fetch LTP for Instrument #{id}: #{response[:remarks]}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("Exception in fetching LTP for Instrument #{id}: #{e.message}")
    nil
  end

  def ohlc
    # Dynamically derive the exchange segment
    exchange_segment = self.exchange_segment
    return nil if exchange_segment == "UNKNOWN"

    # Call the API using the derived segment and security ID
    response = Dhanhq::API::MarketFeed.ohlc({ exchange_segment => [ security_id.to_i ] })

    # Check the response status and return the OHLC or log an error
    if response["status"] == "success"
      response.dig("data", exchange_segment, security_id.to_s)
    else
      Rails.logger.error("Failed to fetch OHLC for Instrument #{id}: #{response[:remarks]}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("Exception in fetching OHLC for Instrument #{id}: #{e.message}")
    nil
  end

  def depth
    # Dynamically derive the exchange segment
    exchange_segment = self.exchange_segment
    return nil if exchange_segment == "UNKNOWN"

    # Call the API using the derived segment and security ID
    response = Dhanhq::API::MarketFeed.quote({ exchange_segment => [ security_id.to_i ] })

    # Check the response status and return the depth or log an error
    if response["status"] == "success"
      response.dig("data", exchange_segment, security_id.to_s)
    else
      Rails.logger.error("Failed to fetch Depth for Instrument #{id}: #{response[:remarks]}")
      nil
    end
  rescue StandardError => e
    Rails.logger.error("Exception in fetching Depth for Instrument #{id}: #{e.message}")
    nil
  end

  def fetch_option_chain(expiry)
    Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id,
      UnderlyingSeg: segment,
      Expiry: expiry
    )
  end

  # Derive the exchange segment string for the API
  def exchange_segment
    exchange_segment_mapping.fetch([ exch_id, segment ], "UNKNOWN")
  end

  private

  # Mapping table for exchange segments
  def exchange_segment_mapping
    {
      [ "NSE", "E" ] => "NSE_EQ",
      [ "NSE", "D" ] => "NSE_FNO",
      [ "NSE", "C" ] => "NSE_CURRENCY",
      [ "BSE", "E" ] => "BSE_EQ",
      [ "BSE", "D" ] => "BSE_FNO",
      [ "BSE", "C" ] => "BSE_CURRENCY",
      [ "MCX", "M" ] => "MCX_COMM",
      [ "NSE", "I" ] => "IDX_I"
    }
  end
end
