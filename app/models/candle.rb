# frozen_string_literal: true

# -----------------------------------------------------------------------------
# Candle – immutable value object representing a single OHLCV bar.
# -----------------------------------------------------------------------------
class Candle
  attr_reader :timestamp, :open, :high, :low, :close, :volume

  # @param ts       [Time, String, Integer] timestamp or epoch (UTC)
  # @param open     [Numeric]
  # @param high     [Numeric]
  # @param low      [Numeric]
  # @param close    [Numeric]
  # @param volume   [Numeric]
  def initialize(ts:, open:, high:, low:, close:, volume:)
    @timestamp = ts.is_a?(Time) ? ts : Time.zone.parse(ts.to_s)
    @open      = PriceMath.round_tick(open.to_f)
    @high      = PriceMath.round_tick(high.to_f)
    @low       = PriceMath.round_tick(low.to_f)
    @close     = PriceMath.round_tick(close.to_f)
    @volume    = volume.to_i
  end

  # Simple helpers ------------------------------------------------------------
  def bullish? = close >= open
  def bearish? = close <  open
end