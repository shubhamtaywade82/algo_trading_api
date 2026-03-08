# frozen_string_literal: true

# Tradable instrument (equity, index, derivative, etc.) with DhanHQ segment and LTP/OHLC helpers.
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
    Dhan::MarketDataService.new(self).fetch_option_chain(expiry)
  end

  def ltp
    Dhan::MarketDataService.new(self).ltp
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
    Dhan::MarketDataService.new(self).historical_ohlc(from_date: from_date, to_date: to_date, oi: oi)
  end

  # Dhan intraday API requires interval: one of "1", "5", "15", "25", "60" (minutes).
  INTRADAY_INTERVALS = %w[1 5 15 25 60].freeze
  DEFAULT_INTRADAY_INTERVAL = '5'

  def intraday_ohlc(interval: DEFAULT_INTRADAY_INTERVAL, oi: false, from_date: nil, to_date: nil, days: 2)
    Dhan::MarketDataService.new(self).intraday_ohlc(
      interval: interval,
      oi: oi,
      from_date: from_date,
      to_date: to_date,
      days: days
    )
  end

  def resolve_instrument_code
    # Get the enum value (e.g., 'OPTCUR' from 'options_currency' key)
    # instrument_before_type_cast returns the database value directly (e.g., 'EQUITY', 'OPTCUR')
    instrument_value = instrument_before_type_cast.to_s

    # Validate it's one of the allowed values for DhanHQ API
    allowed = %w[INDEX FUTIDX OPTIDX EQUITY FUTSTK OPTSTK FUTCOM OPTFUT FUTCUR OPTCUR]
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

  def expiry_list
    Dhan::MarketDataService.new(self).expiry_list
  end
end
