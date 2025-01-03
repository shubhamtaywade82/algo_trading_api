class Order < ApplicationRecord
  # Validations
  validates :ticker, :action, :quantity, :status, presence: true
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
