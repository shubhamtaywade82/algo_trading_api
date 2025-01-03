class Instrument < ApplicationRecord
  # Associations
  belongs_to :exchange
  belongs_to :segment
  belongs_to :exchange_segment
  has_one :mis_detail, dependent: :destroy

  delegate :code, to: :exchange_segment, allow_nil: true, prefix: true

  # Validations
  validates :security_id, presence: true

  # Scopes
  scope :equities, -> { where(instrument_type: "EQ") }
  scope :indices, -> { where(instrument_type: "INDEX") }
  scope :currencies, -> { where(segment: "C") }
  scope :expiring_soon, -> { where(expiry_flag: "1") }

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
      UnderlyingSeg: exchange_segment_code,
      Expiry: expiry
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{id}: #{e.message}")
    nil
  end


  def expiry_list
    Dhanhq::API::Option.expiry_list(
      UnderlyingScrip: security_id,
      UnderlyingSeg: exchange_segment_code,
    )
  end
end
