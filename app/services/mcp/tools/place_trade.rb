# frozen_string_literal: true

module Mcp
  module Tools
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
        unless ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
          return { error: 'Dhan not configured. Set DHAN_CLIENT_ID and complete login at /auth/dhan/login.' }
        end

        payload = {
          security_id: (args['security_id'] || args[:security_id]).to_s.to_i,
          exchange_segment: (args['exchange_segment'] || args[:exchange_segment]).to_s,
          transaction_type: (args['transaction_type'] || args[:transaction_type]).to_s.upcase,
          quantity: (args['quantity'] || args[:quantity]).to_i,
          product_type: (args['product_type'] || args[:product_type]).to_s,
          order_type: (args['order_type'] || args[:order_type]).presence&.upcase || 'LIMIT',
          validity: 'DAY'
        }
        payload[:price] = (args['price'] || args[:price]).to_f if payload[:order_type] == 'LIMIT'

        if ENV['PLACE_ORDER'] != 'true'
          return { dry_run: true, message: 'PLACE_ORDER is not true; order not sent.', payload: payload }
        end

        order = DhanHQ::Models::Order.new(payload)
        order.save
        {
          order_id: order.order_id || order.id,
          order_status: order.order_status || order.status,
          payload: payload
        }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end
