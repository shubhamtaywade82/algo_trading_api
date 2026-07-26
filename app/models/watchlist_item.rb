# A single instrument entry on a Watchlist, bucketed by holding horizon.
class WatchlistItem < ApplicationRecord
  belongs_to :watchlist
  belongs_to :instrument

  validates :bucket, inclusion: { in: %w[intraday swing long_term] }
end
