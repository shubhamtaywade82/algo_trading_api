# frozen_string_literal: true

class Derivative < ApplicationRecord
  # Associations
  belongs_to :instrument

  # Validations
  validates :strike_price, :option_type, :expiry_date, presence: true
end
