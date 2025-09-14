# frozen_string_literal: true

# -----------------------------------------------------------------------------
# CandleSeries – an in‑memory, enumerable collection of Candle objects plus a
# rich toolbox of price‑action and indicator helpers.  No database required.
# -----------------------------------------------------------------------------
class CandleSeries
  include Enumerable

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
  # Accepts either the “array‑of‑hashes” format or the columnar format that
  # DhanHQ sometimes serves ({ 'open' => [...], 'high' => [...], ... }).
  # ---------------------------------------------------------------------------
  def load_from_raw(response)
    normalise_candles(response).each do |row|
      @candles << Candle.new(
        ts: row[:timestamp],
        open: row[:open],
        high: row[:high],
        low: row[:low],
        close: row[:close],
        volume: row[:volume]
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Normalises DhanHQ responses into an array of uniform hashes
  # ---------------------------------------------------------------------------
  def normalise_candles(resp)
    return [] if resp.blank?
    return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

    raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp['high'].is_a?(Array)

    size = resp['high'].size
    (0...size).map do |i|
      {
        open: resp['open'][i].to_f,
        close: resp['close'][i].to_f,
        high: resp['high'][i].to_f,
        low: resp['low'][i].to_f,
        timestamp: Time.zone.at(resp['timestamp'][i]),
        volume: resp['volume'][i].to_i
      }
    end
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

  # ---------------------------------------------------------------------------
  # Indicators (ATR, RSI, MACD, etc.) – leverage TechnicalAnalysis & RTA gems
  # ---------------------------------------------------------------------------
  def atr(period = 14)
    val = TechnicalAnalysis::Atr.calculate(hlc, period: period).first.atr
    { atr: val }
  end

  def rsi(period = 14)
    val = RubyTechnicalAnalysis::RelativeStrengthIndex.new(series: closes, period: period).call
    { rsi: val }
  end

  def moving_average(period = 20)
    ma = RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period)
    { sma: ma.sma, ema: ma.ema, wma: ma.wma }
  end

  def sma(period = 20) = { sma: RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period).sma }
  def ema(period = 20) = { ema: RubyTechnicalAnalysis::MovingAverages.new(series: closes, period: period).ema }

  def macd(fast_period = 12, slow_period = 26, signal_period = 9)
    line, signal, hist = RubyTechnicalAnalysis::Macd.new(
      series: closes,
      fast_period: fast_period,
      slow_period: slow_period,
      signal_period: signal_period
    ).call

    { macd: line, signal: signal, hist: hist }
  end

  # Rate of Change – returns an array with nil values for the initial window
  def rate_of_change(period = 5)
    return { roc: nil } if closes.size < period + 1

    roc_series = closes.map.with_index do |price, idx|
      if idx < period
        nil
      else
        prev = closes[idx - period]
        ((price - prev) / prev.to_f) * 100.0
      end
    end

    { roc: roc_series }
  end

  # ---------------------------------------------------------------------------
  # Price‑action utilities (swing points, liquidity grabs, inside bars…)
  # ---------------------------------------------------------------------------
  def swing_high?(index, lookback = 2)
    res = _swing?(:high, :>, index, lookback)
    { swing_high: res }
  end

  def swing_low?(index, lookback = 2)
    res = _swing?(:low, :<, index, lookback)
    { swing_low: res }
  end

  # ---------------------------------------------------------------------------
  # Price-action utilities (unchanged outputs but wrapped in hashes where
  # meaningful).
  # ---------------------------------------------------------------------------
  def recent_highs(n = 20) = { highs: candles.last(n).map(&:high) }
  def recent_lows(n = 20)  = { lows:  candles.last(n).map(&:low)  }

  def previous_swing_high = recent_highs.sort[-2]
  def previous_swing_low  = recent_lows.sort[1]

  def liquidity_grab_up?(lookback: 20)
    res = _liquidity?(:up, lookback)
    { liquidity_grab_up: res }
  end

  def liquidity_grab_down?(lookback: 20)
    res = _liquidity?(:down, lookback)
    { liquidity_grab_down: res }
  end

  def inside_bar?(i)
    return false if i < 1

    curr = candles[i]
    prev = candles[i - 1]
    curr.high < prev.high && curr.low > prev.low
  end

  # ---------------------------------------------------------------------------
  # Trend utilities (Adaptive Supertrend, Bollinger, Donchian…)
  # ---------------------------------------------------------------------------
  def supertrend_signal
    indicator   = Indicators::AdaptiveSupertrend.new(series: self)
    trend_line  = indicator.call
    latest_trend = trend_line.last
    return nil unless latest_trend

    latest_close = closes.last

    return :bullish if latest_close > latest_trend

    :bearish if latest_close < latest_trend
  end

  def bollinger_bands(period: 20)
    return nil if candles.size < period

    bb = RubyTechnicalAnalysis::BollingerBands.new(series: closes, period: period).call
    { upper: bb[0], lower: bb[1], middle: bb[2] }
  end

  def donchian_channel(period: 20)
    return nil if candles.size < period

    dc = candles.map { |c| { date_time: c.timestamp, value: c.close } }
    { donchian: TechnicalAnalysis::Dc.calculate(dc, period: period) }
  end

  # ---------------------------------------------------------------------------
  private

  # Helper for array‑of‑hashes input
  def slice_candle(c)
    {
      open: c[:open]  || c['open'],
      high: c[:high]  || c['high'],
      low: c[:low] || c['low'],
      close: c[:close] || c['close'],
      timestamp: c[:timestamp] || c['timestamp'],
      volume: c[:volume] || c['volume'] || 0
    }
  end

  def _swing?(attr, cmp, index, lookback)
    return false if index < lookback || index + lookback >= candles.size

    current = candles[index].public_send(attr)
    left    = candles[(index - lookback)...index].map(&attr)
    right   = candles[(index + 1)..(index + lookback)].map(&attr)

    cmp == :> ? (current > left.max && current > right.max) : (current < left.min && current < right.min)
  end

  # --- liquidity helper -----------------------------------------------------
  def _liquidity?(dir, lookback)
    if dir == :up
      # use previous local swing high within lookback window
      high_prev = highs.last(lookback + 1)[0...-1].max
      high_now  = highs.last
      high_now > high_prev && closes.last < high_prev && candles.last.bearish?
    else
      low_prev = lows.last(lookback + 1)[0...-1].min
      low_now  = lows.last
      low_now < low_prev && closes.last > low_prev && candles.last.bullish?
    end
  end
end

