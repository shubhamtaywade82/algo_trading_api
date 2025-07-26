class IntradayAnalysis < ApplicationRecord
  validates :symbol, :timeframe, :atr, :atr_pct, :calculated_at, presence: true
  scope :for, ->(symbol, tf = '5m') { where(symbol: symbol.upcase, timeframe: tf).order(calculated_at: :desc).first }
end
