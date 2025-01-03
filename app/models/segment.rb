class Segment < ApplicationRecord
  has_many :exchange_segments
  has_many :exchanges, through: :exchange_segments
  has_many :instruments, through: :exchange_segments

  validates :segment_code, presence: true, uniqueness: true
  validates :description, presence: true
end
