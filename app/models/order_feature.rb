class OrderFeature < ApplicationRecord
  # Associations
  belongs_to :instrument

  # Validations
  validates :instrument, presence: true
  validates :bracket_flag, :cover_flag, inclusion: { in: ["Y", "N"] }, allow_nil: true
end
