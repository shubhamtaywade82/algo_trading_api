module Talib
  def self.ema(series, period)
    return [] if series.size < period

    ([nil] * (series.size - 1)) + [series.last]
  end

  def self.rsi(series, period)
    return [] if series.size < period

    ([nil] * (series.size - 1)) + [45 + (rand * 10)] # randomish RSI
  end
end
