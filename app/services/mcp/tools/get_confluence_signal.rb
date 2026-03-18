# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that computes the deterministic confluence signal from candles.
    class GetConfluenceSignal
      def self.name
        'get_confluence_signal'
      end

      def self.definition
        {
          name: name,
          title: 'Confluence Signal',
          description: 'Returns confluence bias/score if threshold is met (uses Market::ConfluenceDetector).',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Index symbol: NIFTY | BANKNIFTY | SENSEX' },
              interval: { type: 'string', description: 'Candle interval (default: 5)', enum: %w[1 5 15] }
            },
            required: %w[symbol]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access
        symbol = opts[:symbol].to_s.upcase
        interval = opts[:interval].presence || '5'

        instrument = resolve_instrument!(symbol)
        return { error: 'Instrument not found' } if instrument.nil?

        candles = fetch_candle_hashes(instrument, interval)
        signal = Market::ConfluenceDetector.call(symbol: symbol, candles: candles)

        if signal.nil?
          {
            symbol: symbol,
            signal: nil,
            reason: 'No confluence threshold met or cooldown active',
            timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
          }
        else
          {
            symbol: signal.symbol,
            bias: signal.bias.to_s,
            net_score: signal.net_score,
            max_score: signal.max_score,
            level: signal.level.to_s,
            close: signal.close,
            atr: signal.atr,
            timestamp: signal.timestamp,
            factors: format_factors(signal.factors)
          }
        end
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def resolve_instrument!(symbol)
          exchange = symbol == 'SENSEX' ? 'bse' : 'nse'
          Instrument.segment_index.find_by(underlying_symbol: symbol, exchange: exchange)
        end

        def fetch_candle_hashes(instrument, interval)
          # CandleSeries is built from DhanHQ intraday OHLC and already normalizes timestamps.
          series = instrument.candle_series(interval: interval)
          series.candles.map do |c|
            {
              timestamp: c.timestamp,
              open: c.open,
              high: c.high,
              low: c.low,
              close: c.close,
              volume: c.volume
            }
          end
        end

        def format_factors(factors)
          return [] if factors.blank?

          factors.map do |f|
            {
              name: f.name,
              value: f.value,
              note: f.note
            }
          end
        end
      end
    end
  end
end

