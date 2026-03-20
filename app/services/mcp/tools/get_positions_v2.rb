# frozen_string_literal: true

module Mcp
  module Tools
    # Production tool: returns enriched positions from Positions::ActiveCache and MarketCache/Orders::Analyzer.
    class GetPositionsV2
      extend ExecutionHelpers
      def self.name
        'get_positions'
      end

      def self.definition
        {
          name: name,
          title: 'Get Positions',
          description: 'Returns open positions with LTP and P&L enrichment (via Positions::ActiveCache + Orders::Analyzer).',
          inputSchema: {
            type: 'object',
            properties: {},
            additionalProperties: false
          }
        }
      end

      def self.execute(args)
        normalize_args!(name, args)
        positions = Positions::ActiveCache.all_positions

        formatted = positions.map { |pos| format_position(pos) }.compact

        {
          count: formatted.size,
          positions: formatted,
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def format_position(pos)
          analysis = Orders::Analyzer.call(pos)
          return nil if analysis.blank?

          {
            trading_symbol: pos['tradingSymbol'] || pos[:trading_symbol],
            security_id: pos['securityId'] || pos[:security_id],
            exchange_segment: pos['exchangeSegment'] || pos[:exchange_segment],
            net_qty: (pos['netQty'] || pos[:net_qty]).to_i,
            entry_price: analysis[:entry_price],
            ltp: analysis[:ltp],
            unrealized_pnl: analysis[:pnl],
            pnl_pct: analysis[:pnl_pct],
            product_type: pos['productType'] || pos[:product_type],
            drv_expiry_date: pos['drvExpiryDate'] || pos[:drv_expiry_date]
          }
        end
      end
    end
  end
end

