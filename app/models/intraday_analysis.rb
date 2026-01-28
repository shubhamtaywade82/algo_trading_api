class IntradayAnalysis < ApplicationRecord
  validates :symbol, :timeframe, :atr, :atr_pct, :calculated_at, presence: true
  scope :for_symbol_timeframe, ->(symbol, tf = '5m') { where(symbol: symbol.to_s.upcase, timeframe: tf).order(calculated_at: :desc) }

  def self.get_for(symbol, tf = '5m')
    for_symbol_timeframe(symbol, tf).first
  end
end
