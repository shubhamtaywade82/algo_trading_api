# frozen_string_literal: true

module Market
  # Service for updating technical analysis (ATR, Trend, Confluence) for key indices.
  class AnalysisUpdater < ApplicationService
    INTERVAL  = '5'.freeze # 5-minute candles
    SYMBOLS   = %w[NIFTY BANKNIFTY SENSEX].freeze

    def call
      candle_map = {}
      SYMBOLS.each do |sym|
        candles = update_symbol(sym)
        candle_map[sym] = candles if candles.present?
      end

      return unless candle_map.any? && ENV['ENABLE_SMC_TREND_NOTIFY'] == 'true'

      Market::SmcTrendNotifier.new(candle_map).call
    end

    private

    def update_symbol(symbol)
      inst = instrument(symbol)
      return nil unless inst

      candles = fetch_candles(inst)
      if candles.blank? || candles.size < 15
        log_warn("#{symbol} - Not enough candles fetched (got #{candles&.size || 0}, need 15)")
        return nil
      end

      # Calculate indicators and record analysis
      atr_value = atr14(candles)
      close = candles.last[:close].to_f
      record_analysis!(symbol, atr_value, close)

      # Trigger confluences
      detect_confluence(symbol, candles)

      candles
    rescue StandardError => e
      log_error("#{symbol} – #{e.class}: #{e.message}")
      nil
    end

    def instrument(symbol)
      Instrument.segment_index.find_by!(underlying_symbol: symbol)
    rescue ActiveRecord::RecordNotFound
      log_error("Instrument not found for #{symbol} in segment index")
      nil
    end

    def fetch_candles(instrument)
      # Use the common market data service via instrument delegation
      # Request 2 days of data to ensure we have enough for ATR14
      resp = instrument.intraday_ohlc(interval: INTERVAL, days: 2)
      return [] if resp.blank?

      # If response is already normalized (MarketDataService might return normalized if we want),
      # but currently instrument.intraday_ohlc returns raw data from gem.
      # CandleSeries has the best normalization logic.
      series = CandleSeries.new(symbol: instrument.underlying_symbol, interval: INTERVAL)
      series.load_from_raw(resp)
      series.hlc # Returns [ {high:, low:, close:, date_time:}, ... ]
    end

    def detect_confluence(symbol, candles)
      signal = Market::ConfluenceDetector.call(symbol: symbol, candles: candles)
      Market::ConfluenceNotifier.call(signal: signal)
    rescue StandardError => e
      log_error("Confluence #{symbol} – #{e.class}: #{e.message}")
    end

    # --- ATR (simple Wilder’s) ----------------------------------------------
    def atr14(candles)
      trs = candles.each_cons(2).map do |prev, cur|
        [
          (cur[:high] - cur[:low]).abs,
          (cur[:high] - prev[:close]).abs,
          (cur[:low]  - prev[:close]).abs
        ].max
      end.last(14)
      trs.sum / 14.0
    end

    def record_analysis!(symbol, atr, close)
      IntradayAnalysis.transaction do
        IntradayAnalysis.where(symbol: symbol, timeframe: '5m').delete_all
        IntradayAnalysis.create!(
          symbol: symbol,
          timeframe: '5m',
          atr: atr,
          atr_pct: (atr / close).round(4),
          last_close: close,
          calculated_at: Time.current
        )
      end
      log_info("#{symbol} ATR14 = #{atr.round(2)} (#{(atr / close * 100).round(2)}%)")
    end
  end
end
