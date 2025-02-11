# frozen_string_literal: true

class Instrument < ApplicationRecord
  # Associations
  has_one :mis_detail, dependent: :destroy
  has_many :derivatives, dependent: :destroy
  has_many :margin_requirements, as: :requirementable, dependent: :destroy
  has_many :order_features, as: :featureable, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :levels, dependent: :destroy

  # Enable nested attributes for associated models
  accepts_nested_attributes_for :derivatives, allow_destroy: true
  accepts_nested_attributes_for :margin_requirements, allow_destroy: true
  accepts_nested_attributes_for :order_features, allow_destroy: true

  # Enums
  enum :exchange, { nse: 'NSE', bse: 'BSE' }
  enum :segment, { index: 'I', equity: 'E', currency: 'C', derivatives: 'D' }, prefix: true
  enum :instrument, {
    index: 'INDEX',
    futures_index: 'FUTIDX',
    options_index: 'OPTIDX',
    equity: 'EQUITY',
    futures_stock: 'FUTSTK',
    options_stock: 'OPTSTK',
    futures_currency: 'FUTCUR',
    options_currency: 'OPTCUR'
  }, prefix: true

  # Validations
  validates :security_id, presence: true

  # Scopes
  scope :expiring_soon, -> { where(expiry_flag: '1') }

  # Class Methods

  # Define searchable attributes for Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      instrument
      instrument_type
      underlying_symbol
      symbol_name
      display_name
      exchange
      segment
      created_at
      updated_at
    ]
  end

  # Define searchable associations for Ransack
  def self.ransackable_associations(_auth_object = nil)
    %w[derivatives margin_requirement mis_detail order_feature]
  end

  # Instance Methods
  include MarketFeedHelper

  # API Methods
  def fetch_option_chain(expiry = nil)
    expiry ||= expiry_list.first
    response = Dhanhq::API::Option.chain(
      UnderlyingScrip: security_id.to_i,
      UnderlyingSeg: exchange_segment,
      Expiry: expiry
    )
    data = response['data']
    return nil unless data

    filtered_data = filter_option_chain_data(data)

    { last_price: data['last_price'], oc: filtered_data }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{id}: #{e.message}")
    nil
  end

  def filter_option_chain_data(data)
    data['oc'].select do |_strike, option_data|
      call_data = option_data['ce']
      put_data = option_data['pe']

      has_call_values = call_data && call_data.except('implied_volatility').values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end
      has_put_values = put_data && put_data.except('implied_volatility').values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end

      has_call_values || has_put_values
    end
  end

  def ltp
    fetch_ltp_from_api
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for Instrument #{security_id}: #{e.message}")
    nil
  end

  def fetch_ltp_from_api
    response = Dhanhq::API::MarketFeed.ltp(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s, 'last_price') : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for Instrument #{id}: #{e.message}")
    nil
  end

  def ohlc
    response = Dhanhq::API::MarketFeed.ohlc(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch OHLC for Instrument #{id}: #{e.message}")
    nil
  end

  def depth
    response = Dhanhq::API::MarketFeed.quote(exch_segment_enum)
    response['status'] == 'success' ? response.dig('data', exchange_segment, security_id.to_s) : nil
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Depth for Instrument #{id}: #{e.message}")
    nil
  end

  # Helper method to check if a value is numeric
  def numeric_value?(value)
    value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end

  def expiry_list
    response = Dhanhq::API::Option.expiry_list(
      UnderlyingScrip: security_id,
      UnderlyingSeg: exchange_segment
    )
    response['data']
  end

  # Generate `exchange_segment` dynamically
  def exchange_segment
    case [exchange.to_sym, segment.to_sym]
    when %i[nse index], %i[bse index] then 'IDX_I'
    when %i[nse equity] then 'NSE_EQ'
    when %i[bse equity] then 'BSE_EQ'
    when %i[nse derivatives] then 'NSE_FNO'
    when %i[bse derivatives] then 'BSE_FNO'
    when %i[nse currency] then 'NSE_CURRENCY'
    when %i[bse currency] then 'BSE_CURRENCY'
    else
      raise "Unsupported exchange and segment combination: #{exchange}, #{segment}"
    end
  end

  private

  def exch_segment_enum
    { exchange_segment => [security_id.to_i] }
  end
end
