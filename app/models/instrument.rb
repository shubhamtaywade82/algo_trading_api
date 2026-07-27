# frozen_string_literal: true

# Tradable instrument (equity, index, derivative, etc.) with DhanHQ segment and LTP/OHLC helpers.
class Instrument < ApplicationRecord
  include InstrumentCandleAccessors
  include InstrumentHelpers

  # Associations
  has_one :mis_detail, dependent: :destroy
  has_many :derivatives, dependent: :destroy
  # Both satellites are 1:1 — the DB enforces it with a unique index on the
  # polymorphic pair — so they are has_one, not has_many. They were declared
  # has_many while `ransackable_associations` already named them in the
  # singular, so association search never resolved.
  has_one :margin_requirement, as: :requirementable, dependent: :destroy, inverse_of: :requirementable
  has_one :order_feature, as: :featureable, dependent: :destroy, inverse_of: :featureable
  has_many :alerts, dependent: :destroy
  has_many :levels, dependent: :destroy
  has_many :quotes, dependent: :destroy
  has_many :position_trackers, as: :watchable, dependent: :destroy
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  # Scoped view over the rows already owned by :watchlist_items above, so it
  # carries the same :dependent option.
  has_one :watchlist_item, -> { where(active: true) },
          as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable

  # Enable nested attributes for associated models
  accepts_nested_attributes_for :derivatives, allow_destroy: true
  accepts_nested_attributes_for :margin_requirement, allow_destroy: true
  accepts_nested_attributes_for :order_feature, allow_destroy: true

  # Enums (explicit attribute types for Rails 8)
  #
  # `exchange`, `segment` and `instrument_code` are declared once, in
  # InstrumentHelpers, which both Instrument and Derivative include. Declaring
  # them again here raised "you tried to define an enum named exchange ...
  # already defined by another enum" and made the class unloadable.
  #
  # There is no `instrument` column — the scrip master's INSTRUMENT field is
  # stored in `instrument_code` — so the enum lives on that column and the
  # scopes are `instrument_code_*`.
  #
  # Do not re-declare `attribute :exchange, :string` (etc.) here: the concern
  # is included above, so a later `attribute` call resets the attribute type
  # and silently discards the enum's value mapping.

  # Validations
  #
  # A DhanHQ security_id is unique *within* an exchange segment, not globally —
  # NSE_EQ 2885 and IDX_I 2885 are different instruments. The previous global
  # uniqueness rejected legitimate rows on any manual create and scanned the
  # whole table to do it.
  validates :security_id, presence: true, uniqueness: { scope: %i[exchange segment] }
  validates :symbol_name, presence: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  # Not seen in the most recent scrip master, so the exchange has stopped
  # listing it. Kept rather than deleted because orders and positions still
  # reference these rows by security_id.
  scope :not_seen_since, ->(time) { where(last_seen_at: ...time) }
  scope :for_segment, ->(segment) { where(exchange_segment: segment.to_s) }
  scope :tradable, lambda {
    active.left_joins(:order_feature)
      .where(order_features: { asm_gsm_flag: [nil, 'N', 'R'] })
  }

  # The pair every DhanHQ payload and every WebSocket tick is addressed by.
  # Backed by index_instruments_on_segment_and_security_id.
  def self.for_tick(exchange_segment:, security_id:)
    find_by(exchange_segment: exchange_segment.to_s, security_id: security_id.to_s)
  end

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
      exchange_segment
      active
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
    # instrument_code_before_type_cast returns the database value directly
    # (e.g. 'EQUITY', 'OPTCUR') rather than the enum key.
    instrument_value = instrument_code_before_type_cast.to_s

    # Validate it's one of the allowed values for DhanHQ API
    allowed = %w[INDEX FUTIDX OPTIDX EQUITY FUTSTK OPTSTK FUTCOM OPTFUT FUTCUR OPTCUR]
    return instrument_value if allowed.include?(instrument_value)

    # Fallback: map through the enum when the raw column holds a key rather
    # than a DhanHQ code.
    mapped_value = Instrument.instrument_codes[instrument_code]
    return mapped_value.to_s if mapped_value && allowed.include?(mapped_value.to_s)

    # Default fallback based on segment.
    case segment.to_s
    when 'index' then 'INDEX'
    when 'equity' then 'EQUITY'
    when 'derivatives' then 'FUTSTK'
    when 'commodity' then 'FUTCOM'
    else 'EQUITY'
    end
  end

  def expiry_list
    Dhan::MarketDataService.new(self).expiry_list
  end
end
