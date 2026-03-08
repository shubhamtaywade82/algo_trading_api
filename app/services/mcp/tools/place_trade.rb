# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for placing a new trade order on DhanHQ via MCP.
    class PlaceTrade
      def self.name
        'place_trade'
      end

      def self.definition
        {
          name: name,
          title: 'Execute trade',
          description: 'Place an order via DhanHQ. Requires PLACE_ORDER=true to actually send. Dry-run otherwise.',
          inputSchema: {
            type: 'object',
            properties: {
              security_id: { type: 'string', description: 'Dhan security ID' },
              exchange_segment: { type: 'string', description: 'e.g. NSE_EQ, NSE_FNO' },
              transaction_type: { type: 'string', description: 'BUY or SELL' },
              quantity: { type: 'integer', description: 'Order quantity' },
              order_type: { type: 'string', description: 'MARKET or LIMIT (default LIMIT)' },
              product_type: { type: 'string', description: 'e.g. INTRADAY, MARGIN, CNC' },
              price: { type: 'number', description: 'Limit price (required for LIMIT)' }
            },
            required: %w[security_id exchange_segment transaction_type quantity product_type]
          }
        }
      end

      def self.execute(args)
        return { error: 'Dhan not configured. Set DHAN_CLIENT_ID and complete login at /auth/dhan/login.' } unless dhan_configured?

        opts = args.with_indifferent_access
        payload = build_payload(opts)

        return { dry_run: true, message: 'PLACE_ORDER is not true; order not sent.', payload: payload } if dry_run?

        place_order(payload)
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def dhan_configured?
          ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
        end

        def dry_run?
          ENV['PLACE_ORDER'] != 'true'
        end

        def build_payload(opts)
          payload = {
            security_id: opts[:security_id].to_s.to_i,
            exchange_segment: opts[:exchange_segment].to_s,
            transaction_type: opts[:transaction_type].to_s.upcase,
            quantity: opts[:quantity].to_i,
            product_type: opts[:product_type].to_s,
            order_type: opts[:order_type].presence&.upcase || 'LIMIT',
            validity: 'DAY'
          }
          payload[:price] = opts[:price].to_f if payload[:order_type] == 'LIMIT'
          payload
        end

        def place_order(payload)
          order = DhanHQ::Models::Order.new(payload)
          order.save
          {
            order_id: order.order_id || order.id,
            order_status: order.order_status || order.status,
            payload: payload
          }
        end
      end
    end
  end
end
