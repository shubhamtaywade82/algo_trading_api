# frozen_string_literal: true

class Order < ApplicationRecord
  # Enums
  enum :transaction_type, { buy: 'BUY', sell: 'SELL' }, prefix: :transaction_type
  enum :product_type, { cnc: 'CNC', intraday: 'INTRADAY', margin: 'MARGIN', mtf: 'MTF', co: 'CO', bo: 'BO' }
  enum :order_type, { limit: 'LIMIT', market: 'MARKET', stop_loss: 'STOP_LOSS', stop_loss_market: 'STOP_LOSS_MARKET' },
       prefix: :order_type
  enum :validity, { day: 'DAY', ioc: 'IOC' }
  enum :order_status,
       { transit: 'TRANSIT', pending: 'PENDING', rejected: 'REJECTED', cancelled: 'CANCELLED', traded: 'TRADED',
         expired: 'EXPIRED' }

  # Associations
  belongs_to :alert, optional: true
  validates :dhan_order_id, presence: true
end
