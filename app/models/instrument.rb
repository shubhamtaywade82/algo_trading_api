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

  def fetch_option_chain(expiry = nil)
    expiry = expiry ? expiry : expiry_list.first
    response = Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id.to_i,
      UnderlyingSeg: exchange_segment,
      Expiry: expiry
    )
    data = response["data"]
    return nil unless data

    filtered_data = data["oc"].select do |strike, option_data|
      call_data = option_data["ce"]
      put_data = option_data["pe"]

      has_call_values = call_data && call_data.except("implied_volatility").values.any? { |v| numeric_value?(v) && v.to_f > 0 }
      has_put_values = put_data && put_data.except("implied_volatility").values.any? { |v| numeric_value?(v) && v.to_f > 0 }

      has_call_values || has_put_values
    end

    { last_price: data["last_price"], oc: filtered_data }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{id}: #{e.message}")
    nil
  end

  # Helper method to check if a value is numeric
  def numeric_value?(value)
    value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
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

  # Define searchable attributes for Ransack
  def self.ransackable_attributes(auth_object = nil)
    [
      "instrument",
      "instrument_type",
      "underlying_symbol",
      "symbol_name",
      "display_name",
      "exchange",
      "segment",
      "created_at",
      "updated_at"
    ]
  end

  # Define searchable associations for Ransack
  def self.ransackable_associations(auth_object = nil)
    [ "derivatives", "margin_requirement", "mis_detail", "order_feature" ]
  end

  private

  def exch_segment_enum
    { exchange_segment => [ security_id.to_i ] }
  end
end
