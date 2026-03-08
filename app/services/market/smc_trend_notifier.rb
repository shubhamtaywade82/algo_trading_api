# frozen_string_literal: true

module Market
  # Event-driven SMC & price-action trend notifier. Runs on the same polling as TA update
  # (e.g. UpdateTechnicalAnalysisJob). Notifies Telegram with current trend and important
  # levels for NIFTY, SENSEX, and BANKNIFTY (BANKNIFTY only when next expiry ≤ 7 days).
  # Triggers when price is near a key level (swing, FVG, OB) or on structure/indicator signal (BOS).
  class SmcTrendNotifier < ApplicationService
    SYMBOLS = %w[NIFTY SENSEX BANKNIFTY].freeze
    LEVEL_PROXIMITY_ATR_MULTIPLE = 0.4
    COOLDOWN_TTL = 15.minutes
    CACHE_KEY = 'smc_trend_notifier:last_sent_at'

    def initialize(candle_map)
      @candle_map = candle_map || {}
    end

    def call
      return if ENV['TELEGRAM_CHAT_ID'].blank?
      return if @candle_map.empty?
      return if cooldown_active?
      return unless ENV['ENABLE_SMC_TREND_NOTIFY'] == 'true'

      snippets = build_snippets
      return if snippets.empty?

      msg = format_message(snippets)
      TelegramNotifier.send_message(msg)
      set_cooldown
      Rails.logger.info "[SMC Trend] Notified: #{snippets.keys.join(', ')}"
    rescue StandardError => e
      Rails.logger.error "[SMC Trend] #{e.class}: #{e.message}"
    end

    private

    def build_snippets
      snippets = {}

      SYMBOLS.each do |symbol|
        candles = @candle_map[symbol]
        next if candles.blank? || candles.size < Market::SmcPriceActionAnalyzer::STRUCTURE_LOOKBACK

        next if symbol == 'BANKNIFTY' && !banknifty_expiry_within_7_days?

        series = build_series(symbol, candles)
        smc = Market::SmcPriceActionAnalyzer.new(series).call
        close = series.closes.last
        atr = atr14(candles)

        triggered = trigger?(smc, close, atr)
        snippets[symbol] = {
          smc: smc[:smc],
          price_action: smc[:price_action],
          close: close,
          atr: atr,
          triggered: triggered
        }
      end

      # Only send if at least one symbol had a trigger (level or signal)
      return {} if snippets.none? { |_, v| v[:triggered] }

      snippets
    end

    def trigger?(smc_result, close, atr)
      smc = smc_result[:smc] || smc_result
      return true if smc[:structure_bias] && smc[:structure_bias] != :neutral

      return true if near_swing_level?(smc, close, atr)
      return true if inside_fvg?(smc, close)
      return true if inside_order_block?(smc, close)

      false
    end

    def near_swing_level?(smc, close, atr)
      return false if atr.nil? || atr <= 0

      threshold = atr * LEVEL_PROXIMITY_ATR_MULTIPLE
      highs = Array(smc[:swing_highs])
      lows = Array(smc[:swing_lows])
      nearest_high = highs.min_by { |h| (h - close).abs }
      nearest_low = lows.min_by { |l| (l - close).abs }

      (nearest_high && (close - nearest_high).abs <= threshold) ||
        (nearest_low && (close - nearest_low).abs <= threshold)
    end

    def inside_fvg?(smc, close)
      bull = smc[:fvg_bullish]
      bear = smc[:fvg_bearish]
      (bull && close >= bull[:bottom] && close <= bull[:top]) ||
        (bear && close >= bear[:bottom] && close <= bear[:top])
    end

    def inside_order_block?(smc, close)
      bull = smc[:order_block_bullish]
      bear = smc[:order_block_bearish]
      (bull && close >= bull[:low] && close <= bull[:high]) ||
        (bear && close >= bear[:low] && close <= bear[:high])
    end

    def banknifty_expiry_within_7_days?
      inst = Instrument.find_by(underlying_symbol: 'BANKNIFTY', segment: 'index')
      return false unless inst

      expiries = inst.expiry_list
      return false if expiries.blank?

      next_expiry = expiries.first
      next_date = next_expiry.is_a?(Date) ? next_expiry : Date.parse(next_expiry.to_s)
      (next_date - Time.zone.today).to_i <= 7
    rescue StandardError
      false
    end

    def build_series(symbol, candles)
      series = CandleSeries.new(symbol: symbol, interval: '5')
      candles.each do |c|
        series.add_candle(Candle.new(
          ts: to_time(c[:timestamp] || c['timestamp']),
          open: (c[:open] || c['open']).to_f,
          high: (c[:high] || c['high']).to_f,
          low: (c[:low] || c['low']).to_f,
          close: (c[:close] || c['close']).to_f,
          volume: (c[:volume] || c['volume']).to_i
        ))
      end
      series
    end

    def atr14(candles)
      return nil if candles.size < 15

      trs = candles.each_cons(2).map do |prev, cur|
        [
          (cur[:high].to_f - cur[:low].to_f).abs,
          (cur[:high].to_f - prev[:close].to_f).abs,
          (cur[:low].to_f - prev[:close].to_f).abs
        ].max
      end.last(14)
      trs.sum / 14.0
    end

    def to_time(ts)
      return Time.current if ts.blank?
      return ts if ts.is_a?(Time)

      if ts.is_a?(Numeric)
        return Time.zone.at(ts > 9_999_999_999 ? ts / 1000.0 : ts)
      end

      str = ts.to_s.strip
      return Time.current if str.empty?

      Time.zone.parse(str) || Time.current
    end

    def format_message(snippets)
      lines = ["\u{1F4CA} *SMC Trend Update*"]
      lines << ''

      snippets.each do |symbol, data|
        smc = data[:smc]
        close = data[:close]
        atr = data[:atr]
        trend = (smc[:structure_bias] || :neutral).to_s.capitalize
        emoji = case trend
                when 'Bullish' then "\u{1F7E2}"
                when 'Bearish' then "\u{1F534}"
                else "\u2B1C"
                end

        lines << "#{emoji} *#{symbol}* #{trend} | LTP \u20B9#{format('%g', close)}"
        lines.concat(level_lines(smc))
        lines << "   ATR: #{atr.round(1)} (#{(atr / close * 100).round(2)}%)" if atr
        lines << ''
      end

      lines << "\u23F0 #{Time.zone.now.strftime('%H:%M %Z')}"
      lines.join("\n")
    end

    def level_lines(smc)
      out = []
      sh = Array(smc[:swing_highs]).last(3)
      sl = Array(smc[:swing_lows]).last(3)
      out << "   SH: #{sh.join(', ')}" if sh.any?
      out << "   SL: #{sl.join(', ')}" if sl.any?

      if (fvg = smc[:fvg_bullish])
        out << "   Bull FVG: #{fvg[:bottom]}\u2013#{fvg[:top]}"
      end
      if (fvg = smc[:fvg_bearish])
        out << "   Bear FVG: #{fvg[:bottom]}\u2013#{fvg[:top]}"
      end
      if (ob = smc[:order_block_bullish])
        out << "   Bull OB: #{ob[:low]}\u2013#{ob[:high]}"
      end
      if (ob = smc[:order_block_bearish])
        out << "   Bear OB: #{ob[:low]}\u2013#{ob[:high]}"
      end

      out
    end

    def cooldown_active?
      Rails.cache.read(CACHE_KEY).present?
    end

    def set_cooldown
      Rails.cache.write(CACHE_KEY, Time.current.to_i, expires_in: COOLDOWN_TTL)
    end
  end
end
