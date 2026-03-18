# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that exits an existing position via Orders::Executor (market order).
    class ExitPosition
      def self.name
        'exit_position'
      end

      def self.definition
        {
          name: name,
          title: 'Exit Position',
          description: 'Exits an existing position using Orders::Executor. Actual broker exit requires PLACE_ORDER=true.',
          inputSchema: {
            type: 'object',
            properties: {
              security_id: { type: 'string', description: 'Dhan security ID' },
              exchange_segment: { type: 'string', description: 'e.g. NSE_FNO' },
              reason: { type: 'string', description: 'Exit reason (optional)' }
            },
            required: %w[security_id exchange_segment]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access
        security_id = opts[:security_id].to_s
        exchange_segment = opts[:exchange_segment].to_s
        reason = opts[:reason].presence || 'MCP_EXIT'

        validate!(security_id: security_id, exchange_segment: exchange_segment)

        position = Positions::ActiveCache.fetch(security_id, exchange_segment)
        return { error: 'Position not found' } unless position

        analysis = Orders::Analyzer.call(position)
        Orders::Executor.call(position, reason, analysis.merge(order_type: 'MARKET'))

        { success: true, reason: reason }
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def validate!(security_id:, exchange_segment:)
          raise ArgumentError, 'security_id is required' if security_id.blank?
          raise ArgumentError, 'exchange_segment is required' if exchange_segment.blank?
        end
      end
    end
  end
end

