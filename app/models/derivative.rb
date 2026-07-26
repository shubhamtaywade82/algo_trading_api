# frozen_string_literal: true

# Represents a derivative financial instrument tied to an underlying asset.
class Derivative < ApplicationRecord
  include InstrumentHelpers

  # Associations
  belongs_to :instrument
  has_many :margin_requirements, as: :requirementable, dependent: :destroy
  has_many :order_features, as: :featureable, dependent: :destroy
  has_many :watchlist_items, as: :watchable, dependent: :nullify, inverse_of: :watchable
  # Scoped view over the rows already owned by :watchlist_items above, so it
  # carries the same :dependent option.
  has_one :watchlist_item, -> { where(active: true) },
          as: :watchable, class_name: 'WatchlistItem', dependent: :nullify, inverse_of: :watchable
  has_many :position_trackers, as: :watchable, dependent: :destroy

  # Validations
  validates :strike_price, :option_type, :expiry_date, presence: true
end
