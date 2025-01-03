class ExchangeSegment < ApplicationRecord
  belongs_to :exchange
  belongs_to :segment
  has_many :instruments

  validates :exchange_segment, presence: true, uniqueness: { scope: [ :exchange_id, :segment_id ] }

  def code
    exchange_segment
  end
end
