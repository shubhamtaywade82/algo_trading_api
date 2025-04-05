# frozen_string_literal: true

class Alert < ApplicationRecord
  validates :ticker, :instrument_type, :order_type, :current_price, :time, :strategy_name, :strategy_id, presence: true
  validates :order_type, inclusion: { in: %w[market limit stop] }
  validates :current_price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  enum :instrument_type, {
    stock: 'stock',
    fund: 'fund',
    dr: 'dr',
    right: 'right',
    bond: 'bond',
    warrant: 'warrant',
    structured: 'structured',
    index: 'index',
    forex: 'forex',
    futures: 'futures',
    spread: 'spread',
    economic: 'economic',
    fundamental: 'fundamental',
    crypto: 'crypto',
    spot: 'spot',
    swap: 'swap',
    option: 'option',
    commodity: 'commodity'
  }, prefix: :instrument

  enum :status, { pending: 'pending', processed: 'processed', failed: 'failed', skipped: 'skipped' }
end
