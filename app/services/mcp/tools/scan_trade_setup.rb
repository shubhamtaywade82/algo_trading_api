# frozen_string_literal: true

module Mcp
  module Tools
    class ScanTradeSetup
      def self.name
        'scan_trade_setup'
      end

      def self.definition
        {
          name: name,
          title: 'Run strategy scanner',
          description: 'Runs option strategy suggestions for an index. Returns suggested strategies and strike analysis.',
          inputSchema: {
            type: 'object',
            properties: {
              index_symbol: { type: 'string', description: 'Index symbol (e.g. NIFTY, BANKNIFTY)' },
              expiry_date: { type: 'string', description: 'Expiry YYYY-MM-DD (optional)' },
              strategy_type: { type: 'string', description: 'intraday or swing (default: intraday)' },
              instrument_type: { type: 'string', description: 'ce or pe (optional)' }
            },
            required: ['index_symbol']
          }
        }
      end

      def self.execute(args)
        index_symbol = args['index_symbol'] || args[:index_symbol]
        raise ArgumentError, 'index_symbol is required' if index_symbol.blank?

        instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol.to_s.upcase)
        raise "Instrument not found: #{index_symbol}" unless instrument

        expiry_date = args['expiry_date'] || args[:expiry_date]
        expiry_date = instrument.expiry_list.find { |e| e == expiry_date } || instrument.expiry_list.first if expiry_date.present?

        params = {
          index_symbol: index_symbol,
          expiry_date: expiry_date,
          strategy_type: args['strategy_type'] || args[:strategy_type] || 'intraday',
          instrument_type: args['instrument_type'] || args[:instrument_type]
        }.compact

        strategies = Option::SuggestStrategyService.call(
          index_symbol: index_symbol,
          expiry_date: expiry_date,
          params: params
        )
        { strategies: strategies }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
