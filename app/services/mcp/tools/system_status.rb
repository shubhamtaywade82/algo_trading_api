# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that returns current system / market readiness flags.
    class SystemStatus
      extend ExecutionHelpers
      def self.name
        'system_status'
      end

      def self.definition
        {
          name: name,
          title: 'System Status',
          description: 'Returns whether the market is open and whether new orders are allowed.',
          inputSchema: {
            type: 'object',
            properties: {},
            additionalProperties: false
          }
        }
      end

      def self.execute(args)
        normalize_args!(name, args)
        now = Time.current
        market_open = market_open?(now)
        active_positions = Positions::ActiveCache.all_positions.count
        allowed_to_trade = market_open && active_positions < 3
        place_order_flag = Orders::Gateway.place_order_enabled?(logger: Rails.logger, source: 'system_status')

        {
          market_open: market_open,
          market_time: now.strftime('%Y-%m-%dT%H:%M:%S%z'),
          active_positions: active_positions,
          allowed_to_trade: allowed_to_trade,
          place_order_flag: place_order_flag
        }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def market_open?(time)
          return false unless MarketCalendar.trading_day?(time.to_date)

          minutes = time.hour * 60 + time.min
          minutes >= 9 * 60 + 15 && minutes <= 15 * 60 + 30
        end
      end
    end
  end
end

