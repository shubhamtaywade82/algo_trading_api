# frozen_string_literal: true

module Market
  # Generates "paper" alerts from 1m Supertrend trigger + 5m confirmation.
  #
  # - 1m: trigger direction (supertrend)
  # - 5m: confirm direction (supertrend) + momentum strength (ADX)
  # - Execution: reuses existing AlertProcessors via AlertProcessorFactory,
  #   but sets alert.metadata.execution_mode = "paper" to avoid Dhan orders.
  class OneMinutePaperTrader < ApplicationService
    SYMBOLS = %w[NIFTY BANKNIFTY SENSEX].freeze
    STRATEGY_NAME = '1m_supertrend_adx'.freeze
    STRATEGY_ID = '1m_supertrend_adx_v1'.freeze

    MIN_ADX_5M = ENV.fetch('PAPER_MIN_ADX_5M', '20').to_f
    DEDUPE_WINDOW = 2.minutes

    def call
      SYMBOLS.each { |sym| process_symbol(sym) }
    end

    private

    def process_symbol(symbol)
      instrument = Instrument.find_by!(underlying_symbol: symbol, segment: 'index')

      # Only one paper position per underlying at a time (simple de-dupe).
      return if Position.where(instrument_id: instrument.id, position_type: 'LONG').where('net_qty > 0').exists?

      series_1m = instrument.candle_series(interval: '1')
      series_5m = instrument.candle_series(interval: '5')

      st_1m = series_1m.supertrend_signal
      st_5m = series_5m.supertrend_signal
      return unless st_1m && st_5m

      adx_5m = last_adx(series_5m)
      return unless adx_5m && adx_5m >= MIN_ADX_5M

      signal_type =
        if st_1m == :bullish && st_5m == :bullish
          'long_entry'
        elsif st_1m == :bearish && st_5m == :bearish
          'short_entry'
        end
      return unless signal_type

      # Avoid firing the exact same signal repeatedly while trend is stable.
      if instrument.alerts.where(strategy_id: STRATEGY_ID, signal_type: signal_type)
                   .where('created_at > ?', DEDUPE_WINDOW.ago).exists?
        return
      end

      alert = instrument.alerts.create!(
        ticker: instrument.underlying_symbol,
        instrument_type: 'index',
        exchange: instrument.exchange_before_type_cast,
        time: Time.current,
        strategy_name: STRATEGY_NAME,
        strategy_id: STRATEGY_ID,
        strategy_type: 'intraday',
        order_type: 'market',
        chart_interval: '1',
        current_price: series_1m.closes.last.to_f,
        signal_type: signal_type,
        metadata: {
          source: 'job',
          execution_mode: 'paper',
          indicators: {
            supertrend_1m: st_1m,
            supertrend_5m: st_5m,
            adx_5m: adx_5m
          }
        }
      )

      AlertProcessorFactory.build(alert).call
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("[Market::OneMinutePaperTrader] instrument missing for #{symbol}: #{e.message}")
    rescue StandardError => e
      Rails.logger.error("[Market::OneMinutePaperTrader] #{symbol} failed: #{e.class} - #{e.message}")
    end

    def last_adx(series_5m)
      out = TechnicalIndicators.call(candles: series_5m.candles, only: %i[adx])
      Array(out[:adx]).compact.last&.to_f
    rescue StandardError
      nil
    end
  end
end

