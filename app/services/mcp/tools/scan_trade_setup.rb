# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for running the strategy scanner via MCP.
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
        opts = args.with_indifferent_access
        instrument = resolve_instrument!(opts[:index_symbol])
        expiry_date = resolve_expiry!(instrument, opts[:expiry_date])

        params = build_params(opts, expiry_date)

        strategies = Option::SuggestStrategyService.call(
          index_symbol: opts[:index_symbol],
          expiry_date: expiry_date,
          params: params
        )

        { strategies: strategies }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def resolve_instrument!(index_symbol)
          raise ArgumentError, 'index_symbol is required' if index_symbol.blank?

          instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol.to_s.upcase)
          raise "Instrument not found: #{index_symbol}" unless instrument

          instrument
        end

        def resolve_expiry!(instrument, requested_expiry)
          return instrument.expiry_list.find { |e| e == requested_expiry } || instrument.expiry_list.first if requested_expiry.present?

          nil # Or whatever default logic is appropriate here if expiry is optional and nil means use first somewhere else
        end

        def build_params(opts, expiry_date)
          {
            index_symbol: opts[:index_symbol],
            expiry_date: expiry_date,
            strategy_type: opts[:strategy_type] || 'intraday',
            instrument_type: opts[:instrument_type]
          }.compact
        end
      end
    end
  end
end
