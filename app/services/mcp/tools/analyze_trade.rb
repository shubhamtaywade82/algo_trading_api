# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that wraps the deterministic trade decision engine.
    class AnalyzeTrade
      def self.name
        'analyze_trade'
      end

      def self.definition
        {
          name: name,
          title: 'Analyze Trade',
          description: 'Runs a deterministic trade decision pipeline and returns a trade proposal (no execution).',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Index symbol: NIFTY | BANKNIFTY | SENSEX' },
              expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD (optional)' }
            },
            required: %w[symbol]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access
        symbol = opts[:symbol].to_s
        expiry = opts[:expiry].presence

        result = Trading::TradeDecisionEngine.call(symbol: symbol, expiry: expiry)
        result_hash = result.to_h
        result_hash[:timestamp] = result_hash[:timestamp]&.iso8601
        result_hash
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end

