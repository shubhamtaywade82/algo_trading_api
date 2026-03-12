# frozen_string_literal: true

module AI
  module Tools
    # Returns current open positions from the DhanHQ API.
    class PositionsTool < BaseTool
      TOOL_NAME   = 'get_positions'
      DESCRIPTION = 'Fetch current open positions from the trading account including P&L, quantity, and instrument details.'
      PARAMETERS  = {
        type: 'object',
        properties: {
          filter: {
            type: 'string',
            description: 'Optional filter: all, profitable, losing',
            enum: %w[all profitable losing]
          }
        },
        required: []
      }.freeze

      def perform(args)
        filter = args['filter'] || 'all'

        raw_positions = Dhanhq::API::Portfolio.positions
        positions     = Array(raw_positions)

        positions = filter_positions(positions, filter)

        formatted = positions.map { |p| format_position(p) }
        total_pnl = formatted.sum { |p| p[:unrealized_pnl] }

        {
          count:     formatted.length,
          filter:    filter,
          total_pnl: total_pnl.round(2),
          positions: formatted,
          timestamp: Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def filter_positions(positions, filter)
        case filter
        when 'profitable' then positions.select { |p| p['unrealizedProfit'].to_f > 0 }
        when 'losing'     then positions.select { |p| p['unrealizedProfit'].to_f < 0 }
        else positions
        end
      end

      def format_position(p)
        pnl = p['unrealizedProfit'].to_f

        {
          symbol:         p['tradingSymbol'],
          security_id:    p['securityId'],
          exchange:       p['exchangeSegment'],
          product:        p['productType'],
          quantity:       p['netQty'].to_i,
          buy_avg:        p['buyAvg'].to_f.round(2),
          ltp:            p['ltp'].to_f.round(2),
          unrealized_pnl: pnl.round(2),
          pnl_pct:        calculate_pnl_pct(p),
          direction:      p['netQty'].to_i > 0 ? 'LONG' : 'SHORT'
        }
      end

      def calculate_pnl_pct(position)
        cost = position['buyAvg'].to_f * position['netQty'].to_i.abs
        return 0.0 if cost.zero?

        ((position['unrealizedProfit'].to_f / cost) * 100).round(2)
      end
    end
  end
end
