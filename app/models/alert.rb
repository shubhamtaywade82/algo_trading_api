class Alert < ApplicationRecord
  validates :ticker, :instrument_type, :order_type, :current_price, :time, :strategy_name, :strategy_id, presence: true
  validates :instrument_type, inclusion: { in: %w[stock index crypto forex] }
  validates :order_type, inclusion: { in: %w[market limit stop] }
  validates :current_price, :high, :low, :volume, :stop_loss, :take_profit, :trailing_stop_loss, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  enum :status, { pending: "pending", processed: "processed", failed: "failed" }
end
