# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for fetching historical or intraday market data via MCP.
    class GetMarketData
      extend ExecutionHelpers
      def self.name
        'get_market_data'
      end

      def self.definition
        {
          name: name,
          title: 'LTP / OHLC market data',
          description: 'Returns last price and OHLC for a security (exchange_segment + symbol).',
          inputSchema: {
            type: 'object',
            properties: {
              exchange_segment: { type: 'string', description: 'e.g. NSE_EQ, IDX_I' },
              symbol: { type: 'string', description: 'Trading symbol (e.g. RELIANCE, NIFTY)' }
            },
            required: %w[exchange_segment symbol]
          }
        }
      end

      def self.execute(args)
        opts = normalize_args!(name, args).with_indifferent_access
        segment = opts[:exchange_segment].to_s
        symbol = opts[:symbol].to_s
        raise ArgumentError, 'exchange_segment and symbol are required' if segment.blank? || symbol.blank?

        inst = DhanHQ::Models::Instrument.find(segment, symbol)
        raise "Instrument not found: #{segment} / #{symbol}" unless inst

        ohlc = inst.ohlc
        data = ohlc.respond_to?(:to_h) ? ohlc.to_h : ohlc
        { exchange_segment: segment, symbol: symbol, ohlc: data }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
