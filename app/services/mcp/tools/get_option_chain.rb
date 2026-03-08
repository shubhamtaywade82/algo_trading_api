# frozen_string_literal: true

module Mcp
  module Tools
    class GetOptionChain
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
        index = args['index'] || args[:index]
        raise ArgumentError, 'index is required' if index.blank?

        instrument = Instrument.segment_index.find_by(underlying_symbol: index.to_s.upcase)
        raise "Instrument not found: #{index}" unless instrument

        expiry = args['expiry'] || args[:expiry]
        expiry = instrument.expiry_list.find { |e| e == expiry } || instrument.expiry_list.first if expiry.present?
        expiry ||= instrument.expiry_list.first
        raise 'No expiry available' unless expiry

        option_chain = instrument.fetch_option_chain(expiry)
        raise 'Failed to fetch option chain' unless option_chain

        last_price = instrument.ltp || option_chain[:last_price]
        iv_rank = Option::ChainAnalyzer.estimate_iv_rank(option_chain)
        historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')

        analyzer = Option::ChainAnalyzer.new(
          option_chain,
          expiry: expiry,
          underlying_spot: last_price,
          iv_rank: iv_rank,
          historical_data: historical_data
        )
        result = analyzer.analyze(strategy_type: 'intraday', signal_type: :ce)

        {
          index: index,
          expiry: expiry,
          last_price: last_price,
          iv_rank: iv_rank,
          analysis: result
        }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
