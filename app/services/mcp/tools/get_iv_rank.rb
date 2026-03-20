# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for computing IV rank (percentile bucketed) for an index option chain.
    class GetIvRank
      extend ExecutionHelpers
      def self.name
        'get_iv_rank'
      end

      def self.definition
        {
          name: name,
          title: 'IV Rank',
          description: 'Computes IV rank from the option chain for an index (NIFTY/BANKNIFTY/SENSEX).',
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
        opts = normalize_args!(name, args).with_indifferent_access
        symbol = opts[:symbol].to_s.upcase
        expiry = opts[:expiry].presence

        instrument = resolve_instrument!(symbol)
        expiry_to_use = expiry.presence || instrument.expiry_list&.first

        return { error: 'No expiry available' } if expiry_to_use.blank?

        chain = instrument.fetch_option_chain(expiry_to_use)
        return { error: 'Option chain unavailable' } if chain.blank?

        iv_rank_raw = Option::ChainAnalyzer.estimate_iv_rank(chain)
        iv_rank_pct = (iv_rank_raw.to_f * 100).round(1)

        {
          symbol: symbol,
          expiry: expiry_to_use,
          iv_rank_pct: iv_rank_pct,
          iv_regime: categorize_iv_rank(iv_rank_pct),
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def resolve_instrument!(symbol)
          return Instrument.segment_index.find_by(underlying_symbol: 'SENSEX', exchange: 'bse') if symbol == 'SENSEX'

          Instrument.segment_index.find_by(underlying_symbol: symbol, exchange: 'nse')
        end

        def categorize_iv_rank(iv_rank_pct)
          case iv_rank_pct
          when 0..20 then 'low'
          when 20..50 then 'normal'
          when 50..80 then 'high'
          else 'extreme'
          end
        end
      end
    end
  end
end

