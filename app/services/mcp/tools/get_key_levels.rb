# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that computes key levels deterministically from recent candles.
    class GetKeyLevels
      def self.name
        'get_key_levels'
      end

      def self.definition
        {
          name: name,
          title: 'Key Levels',
          description: 'Computes VWAP, PDH/PDL, ATR14 and simple support/resistance ranges from intraday candles.',
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

        expiry = instrument.expiry_list&.first
        candles = fetch_candle_hashes(instrument, interval)
        return { error: 'Insufficient candle data' } if candles.size < 10

        vwap = calculate_vwap(candles)
        pdh, pdl = previous_day_high_low(candles)
        atr = calculate_atr14(candles)
        support, resistance = recent_support_resistance(candles)

        {
          symbol: symbol,
          expiry: expiry,
          vwap: vwap.round(2),
          pdh: pdh&.round(2),
          pdl: pdl&.round(2),
          atr: atr&.round(2),
          support: support&.round(2),
          resistance: resistance&.round(2),
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
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

        def calculate_vwap(candles)
          total_vol = candles.sum { |c| c[:volume].to_f }
          return candles.sum { |c| c[:close].to_f } / candles.size.to_f if total_vol.zero?

          candles.sum { |c| c[:close].to_f * c[:volume].to_f } / total_vol
        end

        def previous_day_high_low(candles)
          by_date = candles.group_by { |c| c[:timestamp].to_date }
          dates = by_date.keys.sort
          return [nil, nil] if dates.size < 2

          prev_date = dates[-2]
          prev = by_date[prev_date]
          [prev.map { |c| c[:high].to_f }.max, prev.map { |c| c[:low].to_f }.min]
        end

        def calculate_atr14(candles)
          trs = []
          candles.each_cons(2) do |prev, cur|
            high_low = (cur[:high].to_f - cur[:low].to_f).abs
            high_close = (cur[:high].to_f - prev[:close].to_f).abs
            low_close = (cur[:low].to_f - prev[:close].to_f).abs
            trs << [high_low, high_close, low_close].max
          end
          return nil if trs.size < 14

          trs.last(14).sum / 14.0
        end

        def recent_support_resistance(candles)
          window = candles.last(30)
          [window.map { |c| c[:low].to_f }.min, window.map { |c| c[:high].to_f }.max]
        end
      end
    end
  end
end

