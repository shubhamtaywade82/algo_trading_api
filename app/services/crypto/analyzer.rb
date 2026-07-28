# frozen_string_literal: true

module Crypto
  # Fetches the multi-timeframe picture for one symbol and runs the detector.
  #
  #   Crypto::Analyzer.call('SOLUSDT') # => Crypto::Setup or nil
  #
  # Nothing is written anywhere: candles are fetched, analysed and dropped.
  # A scan is a pure read of Binance's public market data, which is what makes
  # it safe to run alongside the DhanHQ order path without touching it.
  class Analyzer
    def self.call(...) = new(...).call

    def initialize(symbol, client: nil, timeframes: Config::TIMEFRAMES)
      @symbol     = Binance::Client.new.normalize_symbol(symbol)
      @client     = client || Binance::Client.new
      @timeframes = timeframes
    end

    attr_reader :symbol

    # @return [Crypto::Setup, nil]
    def call
      reports = build_reports
      return nil if reports.nil?

      SetupDetector.call(symbol: symbol, reports: reports)
    end

    # The same analysis without the gates — every timeframe's read, for the
    # `crypto:report` task and for debugging why a chart did *not* alert.
    def reports
      @reports ||= build_reports
    end

    private

    def build_reports
      out = {}

      @timeframes.each do |timeframe|
        series = fetch(timeframe)
        return nil if series.nil? || series.size < 30

        out[timeframe] = Smc::TimeframeReport.new(series)
      end

      out
    rescue StandardError => e
      Rails.logger.error("[Crypto::Analyzer] #{symbol} analysis failed: #{e.class} - #{e.message}")
      nil
    end

    def fetch(timeframe)
      @client.series(symbol: symbol, interval: timeframe, limit: Config::CANDLE_LIMITS.fetch(timeframe, 200))
    rescue Binance::Error => e
      Rails.logger.error("[Crypto::Analyzer] #{symbol} #{timeframe} fetch failed: #{e.message}")
      nil
    end
  end
end
