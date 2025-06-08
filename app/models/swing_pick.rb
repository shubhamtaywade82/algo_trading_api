class SwingPick < ApplicationRecord
  belongs_to :instrument

  enum :status, { pending: 0, triggered: 1, closed: 2 }
end
