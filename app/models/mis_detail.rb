# frozen_string_literal: true

class MisDetail < ApplicationRecord
  belongs_to :instrument

  validates :mis_leverage, presence: true

  # Ransack attributes
  def self.ransackable_attributes(_auth_object = nil)
    %w[id mis_leverage co_leverage bo_leverage instrument_id created_at updated_at]
  end
end
