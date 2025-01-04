class Instrument < ApplicationRecord
  # Associations
  has_one :mis_detail, dependent: :destroy
  has_many :derivatives, dependent: :destroy
  has_many :margin_requirements, dependent: :destroy
  has_many :order_features, dependent: :destroy

  enum :exchange, { nse: "NSE", bse: "BSE" }
  enum :segment, { index: "I", equity: "E", currency: "C", derivatives: "D" }, prefix: true
  enum :instrument, {
    index: "INDEX",
    futures_index: "FUTIDX",
    options_index: "OPTIDX",
    equity: "EQUITY",
    futures_stock: "FUTSTK",
    options_stock: "OPTSTK",
    futures_currency: "FUTCUR",
    options_currency: "OPTCUR"
  }, prefix: true


  # Validations
  validates :security_id, presence: true

  # Scopes
  # scope :equities, -> { where(instrument: equities) }
  # scope :indices, -> { where(instrument: :index) }
  # scope :currencies, -> { where(segment: "C") }
  scope :expiring_soon, -> { where(expiry_flag: "1") }

  # API Methods
  def ltp
    response = Dhanhq::API::MarketFeed.ltp(exch_segment_enum)
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s, "last_price") : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for Instrument #{id}: #{e.message}")
    nil
  end

  def ohlc
    response = Dhanhq::API::MarketFeed.ohlc(exch_segment_enum)
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch OHLC for Instrument #{id}: #{e.message}")
    nil
  end

  def depth
    response = Dhanhq::API::MarketFeed.quote(exch_segment_enum)
    response["status"] == "success" ? response.dig("data", exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for Instrument #{id}: #{e.message}")
    nil
  end

  def fetch_option_chain(expiry)
    response = Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id.to_i,
      UnderlyingSeg: exchange_segment,
      Expiry: expiry
    )
    response["data"]
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{id}: #{e.message}")
    nil
  end

  def expiry_list
    response = Dhanhq::API::Option.expiry_list(
      UnderlyingScrip: security_id,
      UnderlyingSeg: exchange_segment,
    )
    response["data"]
  end

  # Generate `exchange_segment` dynamically
  def exchange_segment
    case [ exchange.to_sym, segment.to_sym ]
    when [ :nse, :index ] then "IDX_I"
    when [ :bse, :index ] then "IDX_I"
    when [ :nse, :equity ] then "NSE_EQ"
    when [ :bse, :equity ] then "BSE_EQ"
    when [ :nse, :derivatives ] then "NSE_FNO"
    when [ :bse, :derivatives ] then "BSE_FNO"
    when [ :nse, :currency ] then "NSE_CURRENCY"
    when [ :bse, :currency ] then "BSE_CURRENCY"
    else
      raise "Unsupported exchange and segment combination: #{exchange}, #{segment}"
    end
  end

  private

  def exch_segment_enum
    { exchange_segment => [ security_id.to_i ] }
  end
end
