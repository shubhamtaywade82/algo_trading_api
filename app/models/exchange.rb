class Exchange < ApplicationRecord
  validates :exch_id, presence: true, uniqueness: true
  validates :name, presence: true
end
