# frozen_string_literal: true

# -----------------------------------------------------------------------------
# Concern to extend the Instrument model with **rate‑limit‑aware** helpers for
# fetching intraday OHLC data from DhanHQ **without** persisting anything.
#
#   inst.candles(interval: '5')   # => Array<Candle>
#   inst.candle_series(interval: '1')    # => CandleSeries (cached 60 s)
# -----------------------------------------------------------------------------
module InstrumentCandleAccessors
  extend ActiveSupport::Concern

  DEFAULT_INTERVAL = '5' # minutes (string for compatibility with DhanHQ)

  # ---------------------------------------------------------------------------
  # === Delegated indicator methods ===========================================
  # ---------------------------------------------------------------------------
  SERIES_DELEGATES = %i[
    atr rsi moving_average sma ema macd rate_of_change
    swing_high? swing_low? recent_highs recent_lows
    previous_swing_high previous_swing_low
    liquidity_grab_up? liquidity_grab_down?
    inside_bar? supertrend_signal bollinger_bands donchian_channel
  ].freeze

  included do
    SERIES_DELEGATES.each do |meth|
      define_method(meth) do |*args, interval: DEFAULT_INTERVAL, **kwargs|
        candle_series(interval: interval).__send__(meth, *args, **kwargs)
      end
    end
  end

  class_methods do
    # Class‑level shortcut. Use segment for symbols that exist in multiple segments (e.g. NIFTY: index vs currency).
    #   Instrument['NIFTY', segment: :index].candle_series(interval: '15')
    #   Instrument['RELIANCE', segment: :equity]
    def [](sym, security_id: nil, segment: nil)
      base = scope_for_segment(segment)
      base.find_by(symbol_name: sym, security_id: security_id) ||
        base.find_by(underlying_symbol: sym, security_id: security_id) ||
        raise(ActiveRecord::RecordNotFound, "Instrument #{sym} not found")
    end

    def scope_for_segment(segment)
      case segment
      when :index, 'index' then segment_index
      when nil then all
      else where(segment: segment)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Public instance helpers
  # ---------------------------------------------------------------------------
  # @param interval [String] interval in **minutes** as accepted by DhanHQ API
  # @param from     [Time]   start time (defaults: 90 days ago per DhanHQ rules)
  # @param to       [Time]   end time   (defaults: market last trading day)
  # ---------------------------------------------------------------------------
  def candle_series(interval: DEFAULT_INTERVAL, from: default_from_date, to: default_to_date)
    raw = fetch_intraday_cached(interval: interval, from: from, to: to)

    CandleSeries.new(symbol: symbol_name, interval: interval).tap do |cs|
      cs.load_from_raw(raw)
    end
  end

  # Returns just the Array<Candle>
  def candles(**kwargs) = candle_series(**kwargs).candles

  # ---------------------------------------------------------------------------
  private

  # --------------- Rate‑limit / caching --------------------------------------
  # Cache key granularity: per‑instrument & interval.
  #   •  1‑minute interval  ⇒  cache 60 s  (≈ real‑time)
  #   •  2‑5 minutes        ⇒  cache 5 min
  #   •  >5 minutes         ⇒  cache equal to interval length.
  # ---------------------------------------------------------------------------
  def fetch_intraday_cached(interval:, from:, to:)
    ttl = cache_ttl_for(interval.to_i)
    key = "intraday_ohlc:#{security_id}:#{interval}"

    Rails.cache.fetch(key, expires_in: ttl) do
      intraday_ohlc(interval: interval, from_date: from.to_date.to_s, to_date: to.to_date.to_s)
    end
  end

  def cache_ttl_for(int)
    return 1.minute  if int <= 1
    return 5.minutes if int <= 5

    int.minutes
  end

  # --------------- Default date helpers --------------------------------------
  def default_to_date
    MarketCalendar.today_or_last_trading_day
  end

  def default_from_date
    default_to_date - 10.days
  end
end
