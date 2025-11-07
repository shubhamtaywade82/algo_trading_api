# frozen_string_literal: true

require 'bigdecimal'

class Instrument < ApplicationRecord
  include InstrumentCandleAccessors
  include InstrumentHelpers

  # Associations
  has_one :mis_detail, dependent: :destroy
  has_many :derivatives, dependent: :destroy
  has_many :margin_requirements, as: :requirementable, dependent: :destroy
  has_many :order_features, as: :featureable, dependent: :destroy
  has_many :alerts, dependent: :destroy
  has_many :levels, dependent: :destroy
  has_many :quotes, dependent: :destroy
  has_many :position_trackers, as: :watchable, dependent: :destroy
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  has_one :watchlist_item, -> { where(active: true) }, as: :watchable, class_name: 'WatchlistItem'

  # Enable nested attributes for associated models
  accepts_nested_attributes_for :derivatives, allow_destroy: true
  accepts_nested_attributes_for :margin_requirements, allow_destroy: true
  accepts_nested_attributes_for :order_features, allow_destroy: true

  # Validations
  validates :security_id, presence: true, uniqueness: true
  validates :symbol_name, presence: true

  # Scopes
  scope :expiring_soon, -> { where(expiry_flag: '1') }
  scope :enabled, -> { where(enabled: true) }

  # Class Methods
  SEGMENT_FROM_EXCHANGE = {
    'IDX_I' => 'index',
    'BSE_IDX' => 'index',
    'NSE_IDX' => 'index',
    'I' => 'index',
    'NSE_EQ' => 'equity',
    'BSE_EQ' => 'equity',
    'E' => 'equity',
    'NSE_FNO' => 'derivatives',
    'BSE_FNO' => 'derivatives',
    'D' => 'derivatives',
    'NSE_CURRENCY' => 'currency',
    'BSE_CURRENCY' => 'currency',
    'C' => 'currency',
    'MCX_COMM' => 'commodity',
    'M' => 'commodity'
  }.freeze

  def self.segment_key_for(segment_code)
    return if segment_code.blank?

    code = segment_code.to_s.upcase.strip
    SEGMENT_FROM_EXCHANGE[code] || code.downcase
  end

  def self.find_by_sid_and_segment(security_id:, segment_code:, symbol_name: nil)
    segment_key = segment_key_for(segment_code)
    return nil unless security_id.present? && segment_key.present?

    sid = security_id.to_s
    instrument = find_by(security_id: sid, segment: segment_key)
    return instrument if instrument.present? || symbol_name.blank?

    find_by(symbol_name: symbol_name.to_s, segment: segment_key)
  end

  # Define searchable attributes for Ransack
  def self.ransackable_attributes(_auth_object = nil)
    %w[
      instrument_code
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
  def subscribe!
    subscribe
  end

  def unsubscribe!
    unsubscribe
  end

  # Places a market BUY order for the underlying instrument and tracks it.
  # @param qty [Integer, nil]
  # @param product_type [String]
  # @param meta [Hash]
  # @return [Object, nil] Order response from gateway
  def buy_market!(qty: nil, product_type: 'INTRADAY', meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise 'Instrument missing segment/security_id' if segment_code.blank? || security.blank?

    ltp = resolve_ltp(segment: segment_code, security_id: security, meta: meta)
    raise 'LTP unavailable' unless ltp

    quantity = qty.to_i.positive? ? qty.to_i : 1

    order = Orders.config.place_market(
      side: 'buy',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :buy, security_id: security),
        ltp: ltp,
        product_type: product_type
      }
    )
    return nil unless order&.respond_to?(:order_id) && order.order_id.present?

    after_order_track!(
      instrument: self,
      order_no: order.order_id,
      segment: segment_code,
      security_id: security,
      side: 'LONG',
      qty: quantity,
      entry_price: ltp,
      symbol: symbol_name || display_name
    )

    order
  end

  # Places a market SELL order to exit the underlying position.
  # @param qty [Integer, nil]
  # @param meta [Hash]
  # @return [Object, nil]
  def sell_market!(qty: nil, meta: {})
    segment_code = exchange_segment
    security = security_id.to_s
    raise 'Instrument missing segment/security_id' if segment_code.blank? || security.blank?

    quantity = if qty.to_i.positive?
                 qty.to_i
               else
                 PositionTracker.active.where(
                   "(watchable_type = 'Instrument' AND watchable_id = ?) OR instrument_id = ?",
                   id, id
                 ).where(security_id: security).sum(:quantity).to_i
               end
    return nil if quantity <= 0

    Orders.config.place_market(
      side: 'sell',
      segment: segment_code,
      security_id: security,
      qty: quantity,
      meta: {
        client_order_id: meta[:client_order_id] || default_client_order_id(side: :sell, security_id: security)
      }
    )
  end

  # API Methods
  def fetch_option_chain(expiry = nil)
    expiry ||= expiry_list.first

    # Check if caching is disabled for fresh data
    freshness_config = AlgoConfig.fetch[:data_freshness] || {}
    disable_caching = freshness_config[:disable_option_chain_caching] || false

    if disable_caching
      return fetch_fresh_option_chain(expiry)
    end

    # Use cached data if available and not stale
    cache_key = "option_chain:#{security_id}:#{expiry}"
    cached_data = Rails.cache.read(cache_key)

    if cached_data && !option_chain_stale?(expiry)
      return cached_data
    end

    # Fetch fresh data and cache it
    fresh_data = fetch_fresh_option_chain(expiry)
    if fresh_data
      cache_duration_minutes = freshness_config[:option_chain_cache_duration_minutes] || 2
      Rails.cache.write(cache_key, fresh_data, expires_in: cache_duration_minutes.minutes)
      Rails.cache.write("#{cache_key}:timestamp", Time.current, expires_in: cache_duration_minutes.minutes)
    end

    fresh_data
  end

  def fetch_fresh_option_chain(expiry)
    data = DhanHQ::Models::OptionChain.fetch(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment,
      expiry: expiry
    )
    return nil unless data

    filtered_data = filter_option_chain_data(data)

    { last_price: data['last_price'], oc: filtered_data }
  rescue StandardError => e
    Rails.logger.error("Failed to fetch Option Chain for Instrument #{security_id}: #{e.message}")
    nil
  end

  def option_chain_stale?(expiry)
    freshness_config = AlgoConfig.fetch[:data_freshness] || {}
    cache_duration_minutes = freshness_config[:option_chain_cache_duration_minutes] || 2

    cache_key = "option_chain:#{security_id}:#{expiry}"
    cached_at = Rails.cache.read("#{cache_key}:timestamp")

    return true unless cached_at

    Time.current - cached_at > cache_duration_minutes.minutes
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

  def expiry_list
    DhanHQ::Models::OptionChain.fetch_expiry_list(
      underlying_scrip: security_id.to_i,
      underlying_seg: exchange_segment
    )
  end

  def option_chain(expiry: nil)
    fetch_option_chain(expiry)
  end

  # Class method to map enum values to CSV codes
  def self.instrument_codes
    {
      'INDEX' => 'INDEX',
      'FUTIDX' => 'FUTIDX',
      'OPTIDX' => 'OPTIDX',
      'EQUITY' => 'EQUITY',
      'FUTSTK' => 'FUTSTK',
      'OPTSTK' => 'OPTSTK',
      'FUTCUR' => 'FUTCUR',
      'OPTCUR' => 'OPTCUR',
      'FUTCOM' => 'FUTCOM',
      'OPTFUT' => 'OPTFUT'
    }
  end
end
