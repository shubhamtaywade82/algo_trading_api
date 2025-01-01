class Instrument < ApplicationRecord
  # Associations
  belongs_to :exchange
  belongs_to :segment
  has_one :mis_detail, dependent: :destroy

  # Enums
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
    "IDX" => "IDX"
  }, prefix: :instrument_type

  # enum :segment, {
  #   "C" => "C",  # Currency
  #   "D" => "D",  # Derivative
  #   "E" => "E",  # Equity
  #   "I" => "I"   # Index
  # }, prefix: :segment

  # enum :expiry_flag, {
  #   "1" => "Immediate",
  #   "H" => "Half Yearly",
  #   "M" => "Monthly",
  #   "Q" => "Quarterly",
  #   "W" => "Weekly"
  # }, prefix: true

  # Validations
  validates :security_id, presence: true, uniqueness: true
  validates :instrument_type, inclusion: { in: Instrument.instrument_types.keys }
  # validates :segment, inclusion: { in: Instrument.segments.keys }

  # Scopes
  scope :equities, -> { where(instrument_type: "EQ") }
  scope :indices, -> { where(instrument_type: "INDEX") }
  # scope :currencies, -> { where(segment: "C") }
  scope :expiring_soon, -> { where(expiry_flag: "1") }

  # Instance Methods
  def display_name
    "#{symbol_name} (#{instrument_type})"
  end

  # def full_segment_name
  #   case segment
  #   when "C" then "Currency"
  #   when "D" then "Derivative"
  #   when "E" then "Equity"
  #   when "I" then "Index"
  #   else "Unknown"
  #   end
  # end

  # API Methods
  def ltp
    response = Dhanhq::API::MarketFeed.ltp({ exchange_segment => [ security_id.to_i ] })
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s, "last_price") : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for Instrument #{id}: #{e.message}")
    nil
  end

  def ohlc
    response = Dhanhq::API::MarketFeed.ohlc({ exchange_segment => [ security_id.to_i ] })
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch OHLC for Instrument #{id}: #{e.message}")
    nil
  end

  def depth
    response = Dhanhq::API::MarketFeed.quote({ exchange_segment => [ security_id.to_i ] })
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for Instrument #{id}: #{e.message}")
    nil
  end

  def fetch_option_chain(expiry)
    Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id,
      UnderlyingSeg: segment_code_for_api,
      Expiry: expiry
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{id}: #{e.message}")
    nil
  end

  # Helper Methods
  def exchange_segment
    exchange_segment_mapping[[ exch_id, segment ]] || "UNKNOWN"
  end

  private

  # Maps exchange and segment to API values
  def exchange_segment_mapping
    {
      [ "NSE", "E" ] => "NSE_EQ",
      [ "NSE", "D" ] => "NSE_FNO",
      [ "NSE", "C" ] => "NSE_CURRENCY",
      [ "BSE", "E" ] => "BSE_EQ",
      [ "BSE", "D" ] => "BSE_FNO",
      [ "BSE", "C" ] => "BSE_CURRENCY",
      [ "NSE", "I" ] => "IDX_I"
    }
  end
end
