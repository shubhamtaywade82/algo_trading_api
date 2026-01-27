# frozen_string_literal: true

class Instrument < ApplicationRecord
  include InstrumentCandleAccessors

  # Associations
  has_one :mis_detail, dependent: :destroy
  has_many :derivatives, dependent: :destroy
  has_many :margin_requirements, as: :requirementable, dependent: :destroy
  has_many :order_features, as: :featureable, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :levels, dependent: :destroy
  has_many :quotes, dependent: :destroy

  # Enable nested attributes for associated models
  accepts_nested_attributes_for :derivatives, allow_destroy: true
  accepts_nested_attributes_for :margin_requirements, allow_destroy: true
  accepts_nested_attributes_for :order_features, allow_destroy: true

  # Enums (explicit attribute types for Rails 8)
  attribute :exchange, :string
  attribute :segment, :string
  attribute :instrument, :string

  enum :exchange, { nse: 'NSE', bse: 'BSE', mcx: 'MCX' }
  enum :segment, { index: 'I', equity: 'E', currency: 'C', derivatives: 'D', commodity: 'M' }, prefix: true
  enum :instrument, {
    index: 'INDEX',
    futures_index: 'FUTIDX',
    options_index: 'OPTIDX',
    equity: 'EQUITY',
    futures_stock: 'FUTSTK',
    options_stock: 'OPTSTK',
    futures_currency: 'FUTCUR',
    options_currency: 'OPTCUR',
    futures_commodity: 'FUTCOM',
    options_commodity: 'OPTFUT'
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
  include InstrumentHelper

  # API Methods
  def fetch_option_chain(expiry = nil)
    expiry ||= expiry_list.first
    response = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment,
      expiry: expiry
    )
    # New API may return different structure - handle both
    data = response.is_a?(Hash) ? (response['data'] || response) : response
    return nil unless data

    last_price = data.is_a?(Hash) ? (data['last_price'] || data[:last_price]) : nil
    oc_data = data.is_a?(Hash) ? (data['oc'] || data[:oc]) : nil
    return nil unless oc_data

    filtered_data = filter_option_chain_data(oc_data)

    { last_price: last_price, oc: filtered_data }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{security_id}: #{e.message}")
    nil
  end

  def filter_option_chain_data(data)
    data.select do |_strike, option_data|
      call_data = option_data.is_a?(Hash) ? (option_data['ce'] || option_data[:ce]) : nil
      put_data = option_data.is_a?(Hash) ? (option_data['pe'] || option_data[:pe]) : nil

      has_call_values = call_data && call_data.except('implied_volatility', :implied_volatility).values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end
      has_put_values = put_data && put_data.except('implied_volatility', :implied_volatility).values.any? do |v|
        numeric_value?(v) && v.to_f.positive?
      end

      has_call_values || has_put_values
    end
  end

  def ltp
    # Use InstrumentHelper's ltp method but add detailed logging for Instrument
    payload = { exchange_segment => [security_id.to_i] }
    Rails.logger.debug("Fetching LTP for Instrument #{security_id} (#{exchange_segment}) with payload: #{payload.inspect}")

    response = DhanHQ::Models::MarketFeed.ltp(payload)
    Rails.logger.debug("LTP API response for Instrument #{security_id}: #{response.inspect}")

    # Extract last_price from nested response structure
    # Response format: {"data" => {"EXCHANGE_SEGMENT" => {"security_id" => {"last_price" => value}}}, "status" => "success"}
    data = response[:data] || response['data'] || response
    unless data
      Rails.logger.warn("No data found in LTP response for Instrument #{security_id}: #{response.inspect}")
      return nil
    end

    segment_data = data[exchange_segment] || data[exchange_segment.to_sym]
    unless segment_data
      Rails.logger.warn("No segment data for #{exchange_segment} in LTP response for Instrument #{security_id}. Available segments: #{data.keys.inspect}")
      return nil
    end

    security_data = segment_data[security_id.to_s] || segment_data[security_id.to_i]
    unless security_data
      Rails.logger.warn("No security data for #{security_id} in segment #{exchange_segment}. Available securities: #{segment_data.keys.inspect}")
      return nil
    end

    ltp_value = security_data[:last_price] || security_data['last_price'] || security_data[:ltp] || security_data['ltp']
    unless ltp_value
      Rails.logger.warn("No last_price found in security data for Instrument #{security_id}. Available keys: #{security_data.keys.inspect}")
      return nil
    end

    Rails.logger.debug("Successfully fetched LTP for Instrument #{security_id}: #{ltp_value}")
    ltp_value.to_f
  rescue StandardError => e
    Rails.logger.error("Failed to fetch LTP for Instrument #{security_id} (#{exchange_segment}): #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    nil
  end

  def quote_ltp
    quote = quotes.order(tick_time: :desc).first
    return nil unless quote

    quote.ltp.to_s.to_f
  rescue StandardError => e
    Rails.logger.error("Failed to fetch latest quote LTP for Instrument #{security_id}: #{e.message}")
    nil
  end


  def historical_ohlc(from_date: nil, to_date: nil, oi: false)
    instrument_code = resolve_instrument_code
    params = {
      security_id: security_id,
      exchange_segment: exchange_segment,
      instrument: instrument_code,
      oi: oi,
      from_date: from_date || (Time.zone.today - 365).to_s,
      to_date: to_date || (Time.zone.today - 1).to_s
    }

    # Only include expiry_code for derivative instruments (futures/options)
    # For equity/index instruments, expiry_code is not needed and may cause errors
    if instrument_code.to_s.match?(/^(FUT|OPT)/)
      params[:expiry_code] = 0
    end

    Rails.logger.debug("Fetching Historical OHLC for Instrument #{security_id} with params: #{params.inspect}")
    DhanHQ::Models::HistoricalData.daily(params)
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Historical OHLC for Instrument #{security_id} (#{underlying_symbol}, segment: #{segment}, exchange: #{exchange}): #{e.message}")
    Rails.logger.error("Parameters used: #{params.inspect}") if defined?(params)
    Rails.logger.error("Resolved instrument_code: #{instrument_code.inspect}") if defined?(instrument_code)
    nil
  end

  def intraday_ohlc(interval: '5', oi: false, from_date: nil, to_date: nil, days: 2)
    to_date ||= if defined?(MarketCalendar) && MarketCalendar.respond_to?(:today_or_last_trading_day)
                  MarketCalendar.today_or_last_trading_day.to_s
                else
                  (Time.zone.today - 1).to_s
                end
    from_date ||= (Date.parse(to_date) - days).to_s

    instrument_code = resolve_instrument_code
    DhanHQ::Models::HistoricalData.intraday(
      security_id: security_id,
      exchange_segment: exchange_segment,
      instrument: instrument_code,
      interval: interval,
      oi: oi,
      from_date: from_date || (Time.zone.today - days).to_s,
      to_date: to_date || (Time.zone.today - 1).to_s
    )
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Intraday OHLC for #{self.class.name} #{security_id}: #{e.message}")
    nil
  end

  def resolve_instrument_code
    # Get the enum value (e.g., 'OPTCUR' from 'options_currency' key)
    # instrument_before_type_cast returns the database value directly (e.g., 'EQUITY', 'OPTCUR')
    instrument_value = instrument_before_type_cast.to_s

    # Validate it's one of the allowed values for DhanHQ API
    allowed = ['INDEX', 'FUTIDX', 'OPTIDX', 'EQUITY', 'FUTSTK', 'OPTSTK', 'FUTCOM', 'OPTFUT', 'FUTCUR', 'OPTCUR']
    return instrument_value if allowed.include?(instrument_value)

    # Fallback: try to get from enum mapping if instrument is set
    if instrument
      mapped_value = Instrument.instruments[instrument]
      return mapped_value.to_s if mapped_value && allowed.include?(mapped_value.to_s)
    end

    # Default fallback based on segment
    case segment.to_s
    when 'index' then 'INDEX'
    when 'equity' then 'EQUITY'
    when 'derivatives' then 'FUTSTK' # Default for derivatives
    when 'commodity' then 'FUTCOM' # Default for commodities
    else 'EQUITY' # Safe default
    end
  end


  # Helper method to check if a value is numeric
  def numeric_value?(value)
    value.is_a?(Numeric) || value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
  end

  def expiry_list
    DhanHQ::Models::OptionChain.fetch_expiry_list(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment
    )
  end



  private

  def exch_segment_enum
    { exchange_segment => [security_id.to_i] }
  end
end
