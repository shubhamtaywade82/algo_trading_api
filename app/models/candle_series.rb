# frozen_string_literal: true

# -----------------------------------------------------------------------------
# CandleSeries – an in‑memory, enumerable collection of Candle objects plus a
# rich toolbox of price‑action and indicator helpers.  No database required.
# -----------------------------------------------------------------------------
class CandleSeries
  include Enumerable
  include CandleSeriesModules::Indicators
  include CandleSeriesModules::PriceAction
  include CandleSeriesModules::Trend

  attr_reader :symbol, :interval, :candles

  # @param symbol   [String]   e.g. "NIFTY"
  # @param interval [String]   e.g. "5" (minutes) – kept for metadata only
  def initialize(symbol:, interval: '5')
    @symbol   = symbol
    @interval = interval
    @candles  = []
  end

  # Enumerable ----------------------------------------------------------------
  def each(&) = candles.each(&)
  def add_candle(candle) = candles << candle

  # ---------------------------------------------------------------------------
  # Bulk loader from raw JSON/HASH returned by DhanHQ intraday_ohlc endpoint.
  # ---------------------------------------------------------------------------
  def load_from_raw(response)
    Market::CandleLoader.call(self, response)
  end

  # ---------------------------------------------------------------------------
  # Quick accessors
  # ---------------------------------------------------------------------------
  def opens   = candles.map(&:open)
  def closes  = candles.map(&:close)
  def highs   = candles.map(&:high)
  def lows    = candles.map(&:low)

  # Technical‑analysis helper structure expected by many TA gems
  def hlc
    candles.map do |c|
      {
        date_time: c.timestamp,
        high: c.high,
        low: c.low,
        close: c.close
      }
    end
  end
end

