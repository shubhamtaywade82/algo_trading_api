# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for retrieving an analyzed option chain via MCP.
    class GetOptionChain
      extend ExecutionHelpers
      def self.name
        'get_option_chain'
      end

      def self.definition
        {
          name: name,
          title: 'Retrieve analyzed option chain',
          description: 'Returns option chain for an index (e.g. NIFTY) with optional expiry. Uses app Instrument and ChainAnalyzer.',
          inputSchema: {
            type: 'object',
            properties: {
              index: { type: 'string', description: 'Underlying symbol (e.g. NIFTY, BANKNIFTY)' },
              expiry: { type: 'string', description: 'Expiry date YYYY-MM-DD (optional)' }
            },
            required: ['index']
          }
        }
      end

      def self.execute(args)
        opts = normalize_args!(name, args).with_indifferent_access
        instrument = resolve_instrument!(opts[:index])
        expiry = resolve_expiry!(instrument, opts[:expiry])

        option_chain = fetch_chain!(instrument, expiry)
        last_price = instrument.ltp || option_chain[:last_price]

        analysis = analyze_chain(instrument, option_chain, expiry, last_price)

        {
          index: opts[:index],
          expiry: expiry,
          last_price: last_price,
          iv_rank: analysis[:iv_rank],
          analysis: analysis[:result]
        }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def resolve_instrument!(index_symbol)
          raise ArgumentError, 'index is required' if index_symbol.blank?

          instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol.to_s.upcase)
          raise "Instrument not found: #{index_symbol}" unless instrument

          instrument
        end

        def resolve_expiry!(instrument, requested_expiry)
          expiry = instrument.expiry_list.find { |e| e == requested_expiry } || instrument.expiry_list.first if requested_expiry.present?
          expiry ||= instrument.expiry_list.first
          raise 'No expiry available' unless expiry

          expiry
        end

        def fetch_chain!(instrument, expiry)
          chain = instrument.fetch_option_chain(expiry)
          raise 'Failed to fetch option chain' unless chain

          chain
        end

        def analyze_chain(instrument, chain, expiry, spot_price)
          iv_rank = Option::ChainAnalyzer.estimate_iv_rank(chain)
          historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')

          analyzer = Option::ChainAnalyzer.new(
            chain,
            expiry: expiry,
            underlying_spot: spot_price,
            iv_rank: iv_rank,
            historical_data: historical_data
          )

          {
            iv_rank: iv_rank,
            result: analyzer.analyze(strategy_type: 'intraday', signal_type: :ce)
          }
        end
      end
    end
  end
end
