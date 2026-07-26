# A named, ranked collection of instruments to track for a given timeframe.
class Watchlist < ApplicationRecord
  has_many :watchlist_items, -> { order(:rank) }, dependent: :delete_all, inverse_of: :watchlist
  has_many :instruments, through: :watchlist_items

  enum :kind, { intraday: 'intraday', swing: 'swing', long_term: 'long_term', custom: 'custom' }

  validates :name, :kind, :timeframe, presence: true
  validates :name, uniqueness: true

  # convenience
  scope :active, -> { where(active: true) }
end
