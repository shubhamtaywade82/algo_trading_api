# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that deterministically maps an option contract request
    # to the exact Dhan tradable instrument identifiers using the scrip master.
    class ResolveDerivative
      def self.name
        'resolve_derivative'
      end

      def self.definition
        {
          name: name,
          description: 'Resolve derivative contract using Dhan scrip master',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Underlying index symbol: NIFTY | BANKNIFTY | SENSEX' },
              expiry: { type: 'string', description: 'Expiry date (YYYY-MM-DD)' },
              strike: { type: 'integer', description: 'Option strike price' },
              option_type: { type: 'string', description: 'CE | PE', enum: %w[CE PE] }
            },
            required: %w[symbol expiry strike option_type]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access

        result = Trading::DerivativeResolver.new(
          symbol: opts[:symbol],
          expiry: opts[:expiry],
          strike: opts[:strike],
          option_type: opts[:option_type]
        ).call

        {
          security_id: result.security_id,
          exchange_segment: result.exchange_segment,
          trading_symbol: result.trading_symbol,
          lot_size: result.lot_size
        }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end

