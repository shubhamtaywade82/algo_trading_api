# frozen_string_literal: true

class MarginRequirement < ApplicationRecord
  # Associations
  belongs_to :instrument

  # Validations
  validates :buy_co_min_margin_per, :sell_co_min_margin_per, numericality: { greater_than_or_equal_to: 0 },
                                                             allow_nil: true
end
