# frozen_string_literal: true

module Screeners
  class PromptBuilder
    class << self
      def build_prompt(md)
        session_label =
          case md[:session]
          when :pre_open   then '⏰ Pre-open'
          when :post_close then '🔒 Post-close'
          else                  '🟢 Live'
          end

        lines = []
        lines << '=== INDIAN EQUITIES STOCKS SCREENER ==='
        lines << "#{session_label} | Frame #{md[:frame]} | Lookback #{md[:lookback]}"
        lines << "Rules: min_price ₹#{fmt(md.dig(:rules,
                                                 :min_price))}, avgVol≥#{md.dig(:rules,
                                                                                :min_avg_vol)}, optionable=#{md.dig(:rules,
                                                                                                                    :optionable)}, limit=#{md.dig(
:rules, :limit
)}"
        lines << ''
        lines << 'INSTRUCTIONS:'
        lines << '- Output a concise **watchlist** for the next trading day or current session.'
        lines << '- Prefer liquid, optionable names with momentum (ATR%/RelVol) or mean reversion near Bollinger with RSI context.'
        lines << '- For each picked stock, print ONE line: `SYMBOL | Bias | Setup | Entry zone | SL | T1/T2 | Rationale`.'
        lines << '- Setup ∈ {Momentum-Breakout, Pullback-Buy, Breakdown, Reversal, Range-Play}.'
        lines << '- Use ONLY provided values; if missing, print `N/A`.'
        lines << "- Return max #{md.dig(:rules, :limit)} names."
        lines << ''
        lines << '=== PAYLOAD ==='

        (md[:stocks] || []).each do |s|
          prev = s[:prev_day] || {}
          ind  = s[:indicators] || {}
          lines << <<~ROW.strip
            ► #{s[:symbol]}
              LTP: #{fmt(s[:ltp])} | Prev O/H/L/C: #{fmt(prev[:open])}/#{fmt(prev[:high])}/#{fmt(prev[:low])}/#{fmt(prev[:close])}
              OHLC(#{md[:frame]}): O#{fmt(s.dig(:ohlc, :open))} H#{fmt(s.dig(:ohlc, :high))} L#{fmt(s.dig(:ohlc, :low))} C#{fmt(s.dig(:ohlc, :close))} Vol #{s.dig(:ohlc, :volume) || 'N/A'} RelVol #{fmt(ind[:rel_vol])}
              ATR14 #{fmt(ind[:atr14])} (#{fmt(ind[:atr_pct])}%) | RSI14 #{fmt(ind[:rsi14])}
              BOLL U#{fmt(ind.dig(:boll, :upper))} M#{fmt(ind.dig(:boll, :middle))} L#{fmt(ind.dig(:boll, :lower))}
              MACD L#{fmt(ind.dig(:macd, :macd))} S#{fmt(ind.dig(:macd, :signal))} H#{fmt(ind.dig(:macd, :hist))}
              SuperTrend #{ind[:supertrend] || 'N/A'} | 20-bar H#{fmt(ind[:hi20])}/L#{fmt(ind[:lo20])}
              Liquidity grabs ↑#{yn(ind[:liq_up])} ↓#{yn(ind[:liq_dn])} | AvgVol20 #{ind[:avg_vol_20] || 'N/A'}
          ROW
        end

        lines << ''
        lines << '=== TASK ==='
        lines << '1) Score & rank with ATR%, RelVol, RSI vs Bollinger, MACD, SuperTrend, 20-bar, liquidity-grab.'
        lines << "2) Output ranked watchlist (≤ #{md.dig(:rules, :limit)}), one-line format exactly:"
        lines << '   `SYMBOL | Bias | Setup | Entry zone | SL | T1/T2 | Rationale`'
        lines << '3) Then add:'
        lines << '   **Screen Summary:** 1–3 bullets.'
        lines << '   **Risk Notes:** 1–3 bullets.'
        lines.join("\n")
      end

      private

      def fmt(x)
        x.is_a?(Numeric) ? x.round(2) : (x || 'N/A')
      end

      def yn(x) = x ? 'yes' : 'no'
    end
  end
end
