# app/services/indicators/holy_grail.rb
# frozen_string_literal: true

require 'ruby_technical_analysis'
require 'technical_analysis'

module Indicators
  class HolyGrail < ApplicationService
    RTA = RubyTechnicalAnalysis
    TA  = TechnicalAnalysis

    EMA_FAST  = 34
    EMA_SLOW  = 100
    RSI_LEN   = 14
    ADX_LEN   = 14
    ATR_LEN   = 20
    MACD_F = 12
    MACD_S = 26
    MACD_SIG = 9

    # ------------------------------------------------------------------
    # Result struct keeps the four “gate” keys first,
    # then the raw indicators you already logged elsewhere.
    # ------------------------------------------------------------------
    Result = Struct.new(
      :bias, :adx, :momentum, :proceed?,
      :sma50, :ema200, :rsi14, :atr14, :macd, :trend,
      keyword_init: true
    ) do
      def to_h = members.zip(values).to_h
    end

    # ------- ctor -----------------------------------------------------
    def initialize(candles:)
      @candles = candles # Dhan hash-of-arrays
      raise ArgumentError, "need ≥ #{EMA_SLOW} candles" if closes.size < EMA_SLOW
    end

    # ------- main -----------------------------------------------------
    def call
      sma50  = sma(EMA_FAST)
      ema200 = ema(EMA_SLOW)
      rsi14  = rsi(RSI_LEN)
      macd_h = macd_hash
      adx14  = adx(ADX_LEN)
      atr14  = atr(ATR_LEN)

      bias =
        if    sma50 > ema200 then :bullish
        elsif sma50 < ema200 then :bearish
        else
          :neutral
        end

      momentum =
        if macd_h[:macd] > macd_h[:signal] && rsi14 > 52
          :up
        elsif macd_h[:macd] < macd_h[:signal] && rsi14 < 48
          :down
        else
          :flat
        end

      proceed =
        case bias
        when :bullish then adx14 >= 25 && momentum == :up
        when :bearish then adx14 >= 25 && momentum == :down
        else false
        end

      trend =
        if ema200 < closes.last && sma50 > ema200 then :up
        elsif ema200 > closes.last && sma50 < ema200 then :down
        else
          :side
        end

      Result.new(
        bias:, adx: adx14, momentum:, proceed?: proceed,
        sma50:, ema200:, rsi14:, atr14:, macd: macd_h, trend:
      )
    end

    # ------- helpers --------------------------------------------------
    private

    def closes = @candles['close'].map(&:to_f)
    def highs  = @candles['high'].map(&:to_f)
    def lows   = @candles['low'].map(&:to_f)
    def stamps = @candles['timestamp'] || []

    # ---------- rows with :date_time required by technical_analysis ---
    def ohlc_rows
      @ohlc_rows ||= highs.each_index.map do |i|
        {
          date_time: Time.zone.at(stamps[i] || 0), # <- NEW
          high: highs[i],
          low: lows[i],
          close: closes[i]
        }
      end
    end

    # — ruby-technical-analysis —
    def sma(len) = closes.last(len).sum / len.to_f
    def ema(len) = RTA::MovingAverages.new(series: closes, period: len).ema
    def rsi(len) = RTA::RelativeStrengthIndex.new(series: closes, period: len).call

    def macd_hash
      m, s, h = RTA::Macd.new(series: closes,
                              fast_period: MACD_F,
                              slow_period: MACD_S,
                              signal_period: MACD_SIG).call
      { macd: m, signal: s, hist: h }
    end

    # — technical_analysis gem —
    def atr(len) = TA::Atr.calculate(ohlc_rows, period: len).last.atr
    def adx(len) = TA::Adx.calculate(ohlc_rows, period: len).last.adx
  end
end
