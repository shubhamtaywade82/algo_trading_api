# frozen_string_literal: true

module AI
  module Tools
    # Fetches OHLC candle data for an instrument via existing DhanHQ services.
    class DhanCandleTool < BaseTool
      TOOL_NAME   = 'get_candle_data'
      DESCRIPTION = 'Fetch OHLC candle data for an NSE/BSE instrument. Returns recent candles with technical indicators (RSI, MACD, Supertrend, Bollinger Bands).'
      PARAMETERS  = {
        type: 'object',
        properties: {
          symbol: {
            type: 'string',
            description: 'Instrument symbol, e.g. NIFTY, BANKNIFTY, RELIANCE'
          },
          interval: {
            type: 'string',
            description: 'Candle interval: 1m, 5m, 15m, 30m, 1d',
            enum: %w[1m 5m 15m 30m 1d]
          },
          limit: {
            type: 'integer',
            description: 'Number of recent candles to return (default 20, max 100)'
          }
        },
        required: %w[symbol interval]
      }.freeze

      def perform(args)
        symbol   = args['symbol'].to_s.upcase
        interval = args['interval'].to_s
        limit    = [args['limit'].to_i.positive? ? args['limit'].to_i : 20, 100].min

        instrument = Instrument.segment_index.find_by(underlying_symbol: symbol) ||
                     Instrument.find_by(trading_symbol: symbol)

        return { error: "Instrument not found: #{symbol}" } unless instrument

        series = instrument.candle_series(interval: interval.delete_suffix('m'))
        return { error: 'No candle data available' } if series.candles.blank?

        recent_candles = series.candles.last(limit).map do |c|
          {
            ts:     c.timestamp&.strftime('%Y-%m-%dT%H:%M:%S'),
            open:   c.open.to_f.round(2),
            high:   c.high.to_f.round(2),
            low:    c.low.to_f.round(2),
            close:  c.close.to_f.round(2),
            volume: c.volume.to_f.round(0)
          }
        end

        {
          symbol:   symbol,
          interval: interval,
          count:    recent_candles.length,
          candles:  recent_candles,
          indicators: {
            rsi:        series.rsi[:rsi]&.round(2),
            macd:       series.macd.transform_values { |v| v&.round(4) },
            supertrend: series.supertrend_signal,
            boll:       series.bollinger_bands(period: 20).transform_values { |v| v&.round(2) },
            atr:        series.atr[:atr]&.round(2),
            ema14:      series.moving_average(14)[:ema]&.round(2)
          },
          ltp: series.closes.last&.round(2)
        }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
