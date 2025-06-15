# app/services/indicators/holy_grail.rb
# frozen_string_literal: true

require 'ruby_technical_analysis'   # MIT gem you already added
require 'technical_analysis'        # GPL gem that ships ATR, ADX, VWAP, …

module Indicators
  class HolyGrail < ApplicationService
    RTA = RubyTechnicalAnalysis       # short-hand
    TA  = TechnicalAnalysis           # second gem
    ATR_PERIOD = 14 # ← match the chart
    PERIODS = {
      sma50: 50,
      ema200: 200,
      rsi: 14,
      atr: 20,
      macd_fast: 12,
      macd_slow: 26,
      macd_sig: 9
    }.freeze

    # ------------------------------------------------------------------
    # Dhan hash-of-arrays
    def initialize(candles:)
      @candles = candles
    end

    # ---------------- public ------------------------------------------
    def call
      {
        sma50: sma(PERIODS[:sma50]),
        ema200: ema(PERIODS[:ema200]),
        rsi14: rsi(PERIODS[:rsi]),
        atr20: atr_wilder(ATR_PERIOD), # atr_gpl(PERIODS[:atr]),
        macd: macd_hash,
        trend: trend
      }
    end

    # ---------------- maths -------------------------------------------
    private

    # ---------- base series helpers ----------
    def closes(len = nil)
      len ? @candles['close'].last(len) : @candles['close']
    end

    def highs             = @candles['high']
    def lows              = @candles['low']
    def volumes           = @candles['volume']

    # ---------- SMA (simple) ----------
    def sma(len) = closes(len).sum / len.to_f

    # ---------- EMA via ruby-technical-analysis ----------
    def ema(len)
      RTA::MovingAverages.new(series: closes, period: len).ema
    end

    # ---------- RSI via ruby-technical-analysis ----------
    def rsi(len)
      RTA::RelativeStrengthIndex.new(series: closes, period: len).call
    end

    # ---------- ATR via technical-analysis (needs array-of-hashes) ----
    def atr_gpl(len)
      return 0 if closes.size < len + 1      # need ≥ len + 1 observations

      vals = TA::Atr.calculate(
               to_hash_rows,                 # helper converts format
               period: len
             )

      last = vals.last
      last.respond_to?(:value) ? last.value : last.atr
    end

    def atr_wilder(len = ATR_PERIOD)
      last = TA::Atr.calculate(to_hash_rows, period: len).last
      last.respond_to?(:value) ? last.value : last.atr
    end

    # helper – turn parallel arrays into [{high:, low:, close:, …}, …]
    def to_hash_rows
      @to_hash_rows ||= highs.each_index.map do |idx|
        {
          high: highs[idx].to_f,
          low: lows[idx].to_f,
          close: closes[idx].to_f,
          volume: volumes[idx]&.to_f,
          date_time: Time.zone.at(@candles['timestamp'][idx])
        }.compact
      end
    end

    # ---------- MACD via ruby-technical-analysis ----------
    def macd_hash
      m, s, h = RTA::Macd.new(
                  series: closes,
                  fast_period: PERIODS[:macd_fast],
                  slow_period: PERIODS[:macd_slow],
                  signal_period: PERIODS[:macd_sig]
                ).call
      { macd: m, signal: s, hist: h }
    end

    # ---------- simple trend classifier ----------
    def trend
      price = closes.last
      return :side unless price

      ema200 = ema(PERIODS[:ema200])
      sma50  = sma(PERIODS[:sma50])

      return :up   if ema200 < price && sma50 > ema200
      return :down if ema200 > price && sma50 < ema200

      :side
    end
  end
end
