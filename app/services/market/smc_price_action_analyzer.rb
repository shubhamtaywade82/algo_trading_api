# frozen_string_literal: true

module Market
  # Builds SMC-lite (structure, FVG, order blocks) and price-action snapshot from a CandleSeries
  # for use in market analysis prompts (e.g. Telegram commands).
  class SmcPriceActionAnalyzer
    SWING_LOOKBACK = 2
    STRUCTURE_LOOKBACK = 50
    FVG_LOOKBACK = 30
    OB_MOVE_BARS = 3

    def initialize(candle_series)
      @series = candle_series
      @candles = candle_series.candles
      @highs = candle_series.highs
      @lows = candle_series.lows
      @closes = candle_series.closes
    end

    def call
      {
        smc: smc_snapshot,
        price_action: price_action_snapshot
      }
    end

    private

    def smc_snapshot
      return empty_smc if @candles.size < STRUCTURE_LOOKBACK

      swing_highs = swing_high_levels
      swing_lows = swing_low_levels
      last_high = swing_highs.last
      last_low = swing_lows.last
      close = @closes.last

      last_bos = last_bos_direction(close, last_high, last_low)
      structure_bias = last_bos || :neutral

      {
        structure_bias: structure_bias,
        last_bos: last_bos,
        swing_highs: swing_highs.last(3).map { |v| v.round(2) },
        swing_lows: swing_lows.last(3).map { |v| v.round(2) },
        fvg_bullish: nearest_fvg_bullish(close),
        fvg_bearish: nearest_fvg_bearish(close),
        order_block_bullish: order_block_bullish,
        order_block_bearish: order_block_bearish
      }
    end

    def price_action_snapshot
      return empty_price_action if @candles.size < 5

      {
        inside_bar: inside_bar_last?,
        swing_highs_recent: swing_high_levels.last(3).map { |v| v.round(2) },
        swing_lows_recent: swing_low_levels.last(3).map { |v| v.round(2) },
        last_candle_bullish: @candles.last.bullish?
      }
    end

    def empty_smc
      {
        structure_bias: :neutral,
        last_bos: nil,
        swing_highs: [],
        swing_lows: [],
        fvg_bullish: nil,
        fvg_bearish: nil,
        order_block_bullish: nil,
        order_block_bearish: nil
      }
    end

    def empty_price_action
      {
        inside_bar: false,
        swing_highs_recent: [],
        swing_lows_recent: [],
        last_candle_bullish: nil
      }
    end

    def swing_high_levels
      levels = []
      start = SWING_LOOKBACK
      finish = @candles.size - 1 - SWING_LOOKBACK
      start.upto(finish) do |i|
        next unless swing_high?(i)

        levels << @highs[i]
      end
      levels
    end

    def swing_low_levels
      levels = []
      start = SWING_LOOKBACK
      finish = @candles.size - 1 - SWING_LOOKBACK
      start.upto(finish) do |i|
        next unless swing_low?(i)

        levels << @lows[i]
      end
      levels
    end

    def swing_high?(i)
      return false if i < SWING_LOOKBACK || i + SWING_LOOKBACK >= @candles.size

      curr = @highs[i]
      left = @highs[(i - SWING_LOOKBACK)...i].max
      right = @highs[(i + 1)..(i + SWING_LOOKBACK)].max
      curr > left && curr > right
    end

    def swing_low?(i)
      return false if i < SWING_LOOKBACK || i + SWING_LOOKBACK >= @candles.size

      curr = @lows[i]
      left = @lows[(i - SWING_LOOKBACK)...i].min
      right = @lows[(i + 1)..(i + SWING_LOOKBACK)].min
      curr < left && curr < right
    end

    def last_bos_direction(close, last_high, last_low)
      return nil unless last_high && last_low

      return :bullish if close > last_high
      return :bearish if close < last_low

      nil
    end

    def nearest_fvg_bullish(close)
      # Bullish FVG: candle i low > candle i-2 high (gap up). Nearest = most recent unfilled above close.
      start = [@candles.size - FVG_LOOKBACK, 2].max
      (start...@candles.size).reverse_each do |i|
        gap_bottom = @highs[i - 2]
        gap_top = @lows[i]
        next unless gap_top > gap_bottom

        filled = (i...@candles.size).any? { |j| @lows[j] <= gap_bottom }
        next if filled
        next unless gap_bottom > close

        return { top: gap_top.round(2), bottom: gap_bottom.round(2) }
      end
      nil
    end

    def nearest_fvg_bearish(close)
      # Bearish FVG: candle i high < candle i-2 low (gap down). Nearest = most recent unfilled below close.
      start = [@candles.size - FVG_LOOKBACK, 2].max
      (start...@candles.size).reverse_each do |i|
        gap_top = @lows[i - 2]
        gap_bottom = @highs[i]
        next unless gap_bottom < gap_top

        filled = (i...@candles.size).any? { |j| @highs[j] >= gap_top }
        next if filled
        next unless gap_top < close

        return { top: gap_top.round(2), bottom: gap_bottom.round(2) }
      end
      nil
    end

    def order_block_bullish
      # Most recent bearish candle before a rally (next OB_MOVE_BARS close higher)
      min_i = OB_MOVE_BARS
      max_i = @candles.size - 1 - OB_MOVE_BARS
      return nil if max_i < min_i

      max_i.downto(min_i) do |i|
        next unless @candles[i].bearish?

        next_candles_higher = (1..OB_MOVE_BARS).all? { |k| @closes[i + k] > @closes[i] }
        next unless next_candles_higher

        return { high: @highs[i].round(2), low: @lows[i].round(2) }
      end
      nil
    end

    def order_block_bearish
      min_i = OB_MOVE_BARS
      max_i = @candles.size - 1 - OB_MOVE_BARS
      return nil if max_i < min_i

      max_i.downto(min_i) do |i|
        next unless @candles[i].bullish?

        next_candles_lower = (1..OB_MOVE_BARS).all? { |k| @closes[i + k] < @closes[i] }
        next unless next_candles_lower

        return { high: @highs[i].round(2), low: @lows[i].round(2) }
      end
      nil
    end

    def inside_bar_last?
      return false if @candles.size < 2

      i = @candles.size - 1
      curr = @candles[i]
      prev = @candles[i - 1]
      curr.high < prev.high && curr.low > prev.low
    end
  end
end
