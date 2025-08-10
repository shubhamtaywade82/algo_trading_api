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
    @open      = open.to_f.round(2)
    @high      = high.to_f.round(2)
    @low       = low.to_f.round(2)
    @close     = close.to_f.round(2)
    @volume    = volume.to_i
  end

  # Simple helpers ------------------------------------------------------------
  def bullish? = close >= open
  def bearish? = close <  open
end