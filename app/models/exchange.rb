class Exchange < ApplicationRecord
  has_many :exchange_segments
  has_many :segments, through: :exchange_segments
  has_many :instruments, through: :exchange_segments

  validates :exch_id, presence: true, uniqueness: true
  validates :name, presence: true
end
