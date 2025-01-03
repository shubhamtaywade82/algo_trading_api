class Position < ApplicationRecord
  # Validations
  validates :ticker, :action, :quantity, :entry_price, :stop_loss_price, :take_profit_price, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
