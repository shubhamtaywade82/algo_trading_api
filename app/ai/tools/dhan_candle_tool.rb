# frozen_string_literal: true

module AI
  module Tools
    # Fetches OHLC candle data + technical indicators via the existing CandleSeries pipeline.
    class DhanCandleTool < Agents::Tool
      description 'Fetch OHLC candle data for an NSE/BSE instrument. Returns recent candles with technical indicators (RSI, MACD, Supertrend, Bollinger Bands, ATR).'

      param :symbol,   type: 'string',  desc: 'Instrument symbol, e.g. NIFTY, BANKNIFTY, RELIANCE'
      param :interval, type: 'string',  desc: 'Candle interval: 1m, 5m, 15m, 30m, 1d'
      param :limit,    type: 'integer', desc: 'Number of recent candles to return (default 20, max 100)', required: false

      def perform(_ctx, symbol:, interval:, limit: 20)
        sym = symbol.to_s.upcase
        lim = [limit.to_i.positive? ? limit.to_i : 20, 100].min

        instrument = Instrument.segment_index.find_by(underlying_symbol: sym) ||
                     Instrument.find_by(trading_symbol: sym)

        return { error: "Instrument not found: #{sym}" } unless instrument

        series = instrument.candle_series(interval: interval.to_s.delete_suffix('m'))
        return { error: 'No candle data available' } if series.candles.blank?

        recent = series.candles.last(lim).map do |c|
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
          symbol:     sym,
          interval:   interval,
          count:      recent.length,
          candles:    recent,
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
