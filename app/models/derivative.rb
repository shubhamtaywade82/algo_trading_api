class Derivative < ApplicationRecord
  # Associations
  belongs_to :instrument

  # Validations
  validates :instrument, presence: true
  validates :strike_price, :option_type, :expiry_date, presence: true
end
