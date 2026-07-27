# frozen_string_literal: true

# A single tradable derivative contract (option or future) from the DhanHQ
# scrip master, optionally linked to the Instrument that is its underlying.
class Derivative < ApplicationRecord
  include InstrumentHelpers

  OPTION_TYPES = %w[CE PE].freeze

  # Associations
  #
  # Optional: a contract is tradable whether or not we have matched its
  # underlying in `instruments`. While this was required, the importer dropped
  # every derivative whose underlying was missing from the master rather than
  # storing it unparented.
  belongs_to :instrument, optional: true
  has_one :margin_requirement, as: :requirementable, dependent: :destroy, inverse_of: :requirementable
  has_one :order_feature, as: :featureable, dependent: :destroy, inverse_of: :featureable
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  # Scoped view over the rows already owned by :watchlist_items above, so it
  # carries the same :dependent option.
  has_one :watchlist_item, -> { where(active: true) },
          as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy

  # Validations
  #
  # Only options carry a strike and a CE/PE type; futures are derivatives too
  # and were rejected outright by the previous unconditional presence checks.
  # (Import goes through activerecord-import, which skips validations, so the
  # old rule silently applied to hand-built records only.)
  validates :security_id, presence: true
  validates :expiry_date, presence: true
  validates :option_type, inclusion: { in: OPTION_TYPES }, allow_nil: true
  validates :strike_price, :option_type, presence: true, if: :option?

  # Mirrors the CHECK constraints added in 20260727140000. See Instrument for
  # why the database, not this, is the real guarantee.
  validates :lot_size, numericality: { greater_than: 0 }, allow_nil: true
  validates :tick_size, :strike_price,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :active, -> { where(active: true) }
  scope :options, -> { where(option_type: OPTION_TYPES) }
  scope :futures, -> { where(option_type: [nil, '']) }
  scope :calls, -> { where(option_type: 'CE') }
  scope :puts, -> { where(option_type: 'PE') }
  scope :not_seen_since, ->(time) { where(last_seen_at: ...time) }
  scope :expiring_on, ->(date) { where(expiry_date: date) }
  scope :unexpired, -> { where(expiry_date: Date.current..) }

  # The one query the option-buying path runs over and over. Column order
  # matches index_derivatives_on_options_chain, so this is an index-ordered
  # range scan rather than a filter over the whole expiry.
  scope :options_chain, lambda { |underlying, expiry_date|
    active.where(underlying_symbol: underlying.to_s.upcase, expiry_date: expiry_date)
      .where(option_type: OPTION_TYPES)
      .order(:strike_price, :option_type)
  }

  # Backed by index_derivatives_on_segment_and_security_id.
  def self.for_tick(exchange_segment:, security_id:)
    find_by(exchange_segment: exchange_segment.to_s, security_id: security_id.to_s)
  end

  # Distinct expiries still available for an underlying, nearest first.
  def self.expiries_for(underlying)
    active.where(underlying_symbol: underlying.to_s.upcase)
      .where(expiry_date: Date.current..)
      .distinct
      .order(:expiry_date)
      .pluck(:expiry_date)
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[
      security_id symbol_name display_name underlying_symbol instrument_code
      instrument_type exchange segment exchange_segment expiry_date
      strike_price option_type expiry_flag active created_at updated_at
    ]
  end

  def self.ransackable_associations(_auth_object = nil)
    %w[instrument margin_requirement order_feature]
  end

  def option?
    OPTION_TYPES.include?(option_type.to_s.upcase)
  end

  def call?
    option_type.to_s.upcase == 'CE'
  end

  def put?
    option_type.to_s.upcase == 'PE'
  end

  def expired?
    expiry_date.present? && expiry_date < Date.current
  end
end
