# frozen_string_literal: true

module Market
  # Computes a net-score confluence signal from 11 technical + structural
  # factors and fires when score crosses a threshold AND state has changed.
  #
  # Usage:
  #   signal = Market::ConfluenceDetector.call(symbol: 'NIFTY', candles: candles)
  #   # => ConfluenceSignal or nil
  class ConfluenceDetector < ApplicationService
    MEDIUM_THRESHOLD = 5
    HIGH_THRESHOLD   = 8
    MAX_SCORE        = 14
    COOLDOWN_TTL     = 45.minutes
    STATE_TTL        = 3.days

    ConfluenceSignal = Struct.new(
      :symbol, :bias, :net_score, :max_score, :level,
      :factors, :close, :atr, :timestamp,
      keyword_init: true
    )

    Factor = Struct.new(:name, :value, :note, keyword_init: true)

    def initialize(symbol:, candles:)
      @symbol  = symbol
      @candles = candles
    end

    def call
      return nil if @candles.size < 50

      series    = build_series
      factors   = compute_factors(series)
      net_score = factors.sum(&:value)

      return nil if net_score.zero?

      bias  = net_score > 0 ? :bullish : :bearish
      level = level_for(net_score.abs)

      return nil if level == :none
      return nil unless should_alert?(bias, level)

      close = @candles.last[:close].to_f
      atr   = compute_atr14

      signal = ConfluenceSignal.new(
        symbol:    @symbol,
        bias:      bias,
        net_score: net_score,
        max_score: MAX_SCORE,
        level:     level,
        factors:   factors,
        close:     close,
        atr:       atr,
        timestamp: candle_timestamp(@candles.last)
      )

      persist_state(bias, net_score, level)
      signal
    end

    private

    # ── Series builder ──────────────────────────────────────────────────────

    def build_series
      series = CandleSeries.new(symbol: @symbol, interval: '5')
      @candles.each do |c|
        series.add_candle(Candle.new(
          ts:     to_time(c[:timestamp] || c['timestamp']),
          open:   (c[:open]   || c['open']   || 0).to_f,
          high:   (c[:high]   || c['high']   || 0).to_f,
          low:    (c[:low]    || c['low']    || 0).to_f,
          close:  (c[:close]  || c['close']  || 0).to_f,
          volume: (c[:volume] || c['volume'] || 0).to_i
        ))
      end
      series
    end

    # ── Factor computation ──────────────────────────────────────────────────

    def compute_factors(series)
      close = series.closes.last
      smc   = Market::SmcPriceActionAnalyzer.new(series).call[:smc]

      momentum = [
        supertrend_factor(series),
        macd_factor(series),
        rsi_factor(series),
        ema20_factor(series, close),
        ema50_factor(series, close)
      ]

      adx = adx_factor(series, momentum.sum(&:value))

      structure = [
        liquidity_factor(series),
        bos_factor(smc),
        fvg_factor(smc),
        ob_factor(smc)
      ]

      price_action = [bollinger_factor(series, close)]

      momentum + [adx] + structure + price_action
    end

    def supertrend_factor(series)
      st = series.supertrend_signal
      case st
      when :bullish then Factor.new(name: 'SuperTrend', value: 2,  note: 'BULLISH')
      when :bearish then Factor.new(name: 'SuperTrend', value: -2, note: 'BEARISH')
      else               Factor.new(name: 'SuperTrend', value: 0,  note: 'Neutral')
      end
    rescue StandardError
      Factor.new(name: 'SuperTrend', value: 0, note: 'Error')
    end

    def macd_factor(series)
      data = series.macd
      line, sig = data[:macd], data[:signal]
      return Factor.new(name: 'MACD', value: 0, note: 'Insufficient data') unless line && sig

      above = line > sig
      Factor.new(
        name:  'MACD',
        value: above ? 1 : -1,
        note:  above ? "Above signal (#{line.round(4)})" : "Below signal (#{line.round(4)})"
      )
    rescue StandardError
      Factor.new(name: 'MACD', value: 0, note: 'Error')
    end

    def rsi_factor(series)
      val = series.rsi[:rsi]
      return Factor.new(name: 'RSI', value: 0, note: 'Insufficient data') unless val

      above = val > 50
      Factor.new(
        name:  'RSI',
        value: above ? 1 : -1,
        note:  "#{val.round(1)} \u2192 #{above ? 'above' : 'below'} 50"
      )
    rescue StandardError
      Factor.new(name: 'RSI', value: 0, note: 'Error')
    end

    def ema20_factor(series, close)
      val = series.ema(20)[:ema]
      return Factor.new(name: 'EMA20', value: 0, note: 'Insufficient data') unless val

      above = close > val
      Factor.new(
        name:  'EMA20',
        value: above ? 1 : -1,
        note:  "#{above ? 'above' : 'below'} EMA20 (#{val.round(2)})"
      )
    rescue StandardError
      Factor.new(name: 'EMA20', value: 0, note: 'Error')
    end

    def ema50_factor(series, close)
      val = series.ema(50)[:ema]
      return Factor.new(name: 'EMA50', value: 0, note: 'Insufficient data') unless val

      above = close > val
      Factor.new(
        name:  'EMA50',
        value: above ? 1 : -1,
        note:  "#{above ? 'above' : 'below'} EMA50 (#{val.round(2)})"
      )
    rescue StandardError
      Factor.new(name: 'EMA50', value: 0, note: 'Error')
    end

    def adx_factor(series, preliminary_net)
      val = adx_value(series)
      return Factor.new(name: 'ADX', value: 0, note: 'Insufficient data') unless val

      if val >= 20
        sign = preliminary_net >= 0 ? 1 : -1
        Factor.new(name: 'ADX', value: sign, note: "#{val.round(1)} \u2192 trend confirmed")
      else
        Factor.new(name: 'ADX', value: 0, note: "#{val.round(1)} \u2192 weak trend")
      end
    end

    def adx_value(series)
      hlc = series.hlc.last(60)
      return nil if hlc.size < 28

      TechnicalAnalysis::Adx.calculate(hlc, period: 14).first&.adx
    rescue StandardError
      nil
    end

    def liquidity_factor(series)
      liq_down = series.liquidity_grab_down?[:liquidity_grab_down]
      liq_up   = series.liquidity_grab_up?[:liquidity_grab_up]

      if liq_down
        Factor.new(name: 'Liquidity Grab', value: 2,  note: 'Bullish reversal grab')
      elsif liq_up
        Factor.new(name: 'Liquidity Grab', value: -2, note: 'Bearish reversal grab')
      else
        Factor.new(name: 'Liquidity Grab', value: 0,  note: 'None')
      end
    rescue StandardError
      Factor.new(name: 'Liquidity Grab', value: 0, note: 'Error')
    end

    def bos_factor(smc)
      case smc[:last_bos]
      when :bullish then Factor.new(name: 'BOS', value: 2,  note: 'BULLISH')
      when :bearish then Factor.new(name: 'BOS', value: -2, note: 'BEARISH')
      else               Factor.new(name: 'BOS', value: 0,  note: 'None')
      end
    end

    def fvg_factor(smc)
      if (bull = smc[:fvg_bullish])
        Factor.new(name: 'FVG', value: 1,  note: "Bullish gap #{fmt(bull[:bottom])}\u2013#{fmt(bull[:top])}")
      elsif (bear = smc[:fvg_bearish])
        Factor.new(name: 'FVG', value: -1, note: "Bearish gap #{fmt(bear[:bottom])}\u2013#{fmt(bear[:top])}")
      else
        Factor.new(name: 'FVG', value: 0,  note: 'None nearby')
      end
    end

    def ob_factor(smc)
      if (bull = smc[:order_block_bullish])
        Factor.new(name: 'Order Block', value: 1,  note: "Bullish OB #{fmt(bull[:low])}\u2013#{fmt(bull[:high])}")
      elsif (bear = smc[:order_block_bearish])
        Factor.new(name: 'Order Block', value: -1, note: "Bearish OB #{fmt(bear[:low])}\u2013#{fmt(bear[:high])}")
      else
        Factor.new(name: 'Order Block', value: 0,  note: 'None nearby')
      end
    end

    def bollinger_factor(series, close)
      bb = series.bollinger_bands
      return Factor.new(name: 'Bollinger', value: 0, note: 'Insufficient data') unless bb

      if close > bb[:middle]
        Factor.new(name: 'Bollinger', value: 1,  note: 'Above midband')
      elsif close < bb[:middle]
        Factor.new(name: 'Bollinger', value: -1, note: 'Below midband')
      else
        Factor.new(name: 'Bollinger', value: 0,  note: 'Mid range')
      end
    rescue StandardError
      Factor.new(name: 'Bollinger', value: 0, note: 'Error')
    end

    # ── State & cooldown ────────────────────────────────────────────────────

    def should_alert?(bias, level)
      prev_score_str = Rails.cache.read(score_key)
      prev_level     = Rails.cache.read(level_key) || '0'
      prev_bias      = case prev_score_str.to_i
                       when 1..Float::INFINITY  then :bullish
                       when -Float::INFINITY..-1 then :bearish
                       end

      cd_key = bias == :bullish ? bull_cooldown_key : bear_cooldown_key
      return false if Rails.cache.read(cd_key)

      return true if prev_bias != bias
      return true if prev_level == 'medium' && level == :high

      false
    end

    def persist_state(bias, net_score, level)
      Rails.cache.write(score_key, net_score.to_s, expires_in: STATE_TTL)
      Rails.cache.write(level_key, level.to_s,     expires_in: STATE_TTL)
      cd_key = bias == :bullish ? bull_cooldown_key : bear_cooldown_key
      Rails.cache.write(cd_key, '1', expires_in: COOLDOWN_TTL)
    end

    def score_key         = "ta:confluence:#{@symbol}:score"
    def level_key         = "ta:confluence:#{@symbol}:level"
    def bull_cooldown_key = "ta:cooldown:#{@symbol}:bull"
    def bear_cooldown_key = "ta:cooldown:#{@symbol}:bear"

    # ── Helpers ──────────────────────────────────────────────────────────────

    def level_for(abs_score)
      return :high   if abs_score >= HIGH_THRESHOLD
      return :medium if abs_score >= MEDIUM_THRESHOLD

      :none
    end

    def compute_atr14
      return nil if @candles.size < 15

      trs = @candles.each_cons(2).map do |prev, cur|
        [
          (cur[:high].to_f  - cur[:low].to_f).abs,
          (cur[:high].to_f  - prev[:close].to_f).abs,
          (cur[:low].to_f   - prev[:close].to_f).abs
        ].max
      end.last(14)
      trs.sum / 14.0
    end

    def candle_timestamp(candle)
      to_time(candle[:timestamp] || candle['timestamp'])
    end

    def to_time(ts)
      return Time.current if ts.blank?
      return ts if ts.is_a?(Time)

      Time.zone.at(ts.to_i)
    end

    def fmt(val)
      format('%g', val.to_f)
    end
  end
end
