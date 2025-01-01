class Segment < ApplicationRecord
  validates :segment_code, presence: true, uniqueness: true
  validates :description, presence: true
end
