# frozen_string_literal: true

# Represents a derivative financial instrument tied to an underlying asset.
class Derivative < ApplicationRecord
  include InstrumentHelper
  # Associations
  belongs_to :instrument
  has_many :margin_requirements, as: :requirementable, dependent: :destroy
  has_many :order_features, as: :featureable, dependent: :destroy

  enum :exchange, {
    nse: 'NSE',
    bse: 'BSE',
    mcx: 'MCX'
  }

  enum :segment, {
    index: 'I',
    equity: 'E',
    currency: 'C',
    derivatives: 'D',
    commodity: 'M'
  }, prefix: true

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
  validates :strike_price, :option_type, :expiry_date, presence: true
end
