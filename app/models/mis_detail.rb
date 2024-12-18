class MisDetail < ApplicationRecord
  belongs_to :instrument

  validates :mis_leverage, presence: true
end
