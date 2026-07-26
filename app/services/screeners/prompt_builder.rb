# frozen_string_literal: true

module Screeners
  # Renders the LLM prompt for the equities screener from a market-data hash.
  class PromptBuilder
    class << self
      def build_prompt(md)
        rules = md[:rules] || {}

        lines = []
        lines << '=== INDIAN EQUITIES STOCKS SCREENER ==='
        lines << "#{session_label(md[:session])} | Frame #{md[:frame]} | Lookback #{md[:lookback]}"
        lines << "Rules: min_price ₹#{fmt(rules[:min_price])}, avgVol≥#{rules[:min_avg_vol]}, " \
                 "optionable=#{rules[:optionable]}, limit=#{rules[:limit]}"
        lines << ''
        lines << 'INSTRUCTIONS:'
        lines << '- Output a concise **watchlist** for the next trading day or current session.'
        lines << '- Prefer liquid, optionable names with momentum (ATR%/RelVol) or mean reversion near Bollinger with RSI context.'
        lines << '- For each picked stock, print ONE line: `SYMBOL | Bias | Setup | Entry zone | SL | T1/T2 | Rationale`.'
        lines << '- Setup ∈ {Momentum-Breakout, Pullback-Buy, Breakdown, Reversal, Range-Play}.'
        lines << '- Use ONLY provided values; if missing, print `N/A`.'
        lines << "- Return max #{rules[:limit]} names."
        lines << ''
        lines << '=== PAYLOAD ==='

        (md[:stocks] || []).each { |s| lines << stock_row(s, md[:frame]) }

        lines << ''
        lines << '=== TASK ==='
        lines << '1) Score & rank with ATR%, RelVol, RSI vs Bollinger, MACD, SuperTrend, 20-bar, liquidity-grab.'
        lines << "2) Output ranked watchlist (≤ #{rules[:limit]}), one-line format exactly:"
        lines << '   `SYMBOL | Bias | Setup | Entry zone | SL | T1/T2 | Rationale`'
        lines << '3) Then add:'
        lines << '   **Screen Summary:** 1–3 bullets.'
        lines << '   **Risk Notes:** 1–3 bullets.'
        lines.join("\n")
      end

      private

      def session_label(session)
        case session
        when :pre_open   then '⏰ Pre-open'
        when :post_close then '🔒 Post-close'
        else                  '🟢 Live'
        end
      end

      def stock_row(stock, frame)
        prev = stock[:prev_day] || {}
        ind  = stock[:indicators] || {}
        <<~ROW.strip
          ► #{stock[:symbol]}
            LTP: #{fmt(stock[:ltp])} | Prev O/H/L/C: #{ohlc_line(prev)}
            OHLC(#{frame}): #{frame_ohlc_line(stock[:ohlc] || {})} RelVol #{fmt(ind[:rel_vol])}
            ATR14 #{fmt(ind[:atr14])} (#{fmt(ind[:atr_pct])}%) | RSI14 #{fmt(ind[:rsi14])}
            BOLL U#{fmt(ind.dig(:boll, :upper))} M#{fmt(ind.dig(:boll, :middle))} L#{fmt(ind.dig(:boll, :lower))}
            MACD L#{fmt(ind.dig(:macd, :macd))} S#{fmt(ind.dig(:macd, :signal))} H#{fmt(ind.dig(:macd, :hist))}
            SuperTrend #{ind[:supertrend] || 'N/A'} | 20-bar H#{fmt(ind[:hi20])}/L#{fmt(ind[:lo20])}
            Liquidity grabs ↑#{yn(ind[:liq_up])} ↓#{yn(ind[:liq_dn])} | AvgVol20 #{ind[:avg_vol_20] || 'N/A'}
        ROW
      end

      def ohlc_line(bar)
        "#{fmt(bar[:open])}/#{fmt(bar[:high])}/#{fmt(bar[:low])}/#{fmt(bar[:close])}"
      end

      def frame_ohlc_line(bar)
        "O#{fmt(bar[:open])} H#{fmt(bar[:high])} L#{fmt(bar[:low])} C#{fmt(bar[:close])} " \
          "Vol #{bar[:volume] || 'N/A'}"
      end

      def fmt(x)
        x.is_a?(Numeric) ? x.round(2) : (x || 'N/A')
      end

      def yn(x) = x ? 'yes' : 'no'
    end
  end
end
