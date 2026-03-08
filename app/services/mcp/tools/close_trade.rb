# frozen_string_literal: true

module Mcp
  module Tools
    class CloseTrade
      def self.name
        'close_trade'
      end

      def self.definition
        {
          name: name,
          title: 'Close position',
          description: 'Close an open position by security_id. Sends exit order (opposite side). Requires PLACE_ORDER=true.',
          inputSchema: {
            type: 'object',
            properties: {
              security_id: { type: 'string', description: 'Dhan security ID of the position' },
              exchange_segment: { type: 'string', description: 'e.g. NSE_EQ, NSE_FNO' },
              net_quantity: { type: 'integer', description: 'Absolute quantity to close' },
              product_type: { type: 'string', description: 'e.g. INTRADAY, MARGIN' },
              transaction_type: { type: 'string', description: 'SELL to close long, BUY to close short' }
            },
            required: %w[security_id exchange_segment net_quantity product_type]
          }
        }
      end

      def self.execute(args)
        unless ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
          return { error: 'Dhan not configured. Set DHAN_CLIENT_ID and complete login.' }
        end

        security_id = (args['security_id'] || args[:security_id]).to_s
        exchange_segment = (args['exchange_segment'] || args[:exchange_segment]).to_s
        net_qty = (args['net_quantity'] || args[:net_quantity]).to_i
        product_type = (args['product_type'] || args[:product_type]).to_s
        transaction_type = (args['transaction_type'] || args[:transaction_type]).to_s.upcase

        transaction_type = net_qty.positive? ? 'SELL' : 'BUY' if transaction_type.blank?
        quantity = net_qty.abs

        payload = {
          security_id: security_id.to_i,
          exchange_segment: exchange_segment,
          transaction_type: transaction_type,
          quantity: quantity,
          order_type: 'MARKET',
          product_type: product_type,
          validity: 'DAY'
        }

        if ENV['PLACE_ORDER'] != 'true'
          return { dry_run: true, message: 'PLACE_ORDER is not true; close order not sent.', payload: payload }
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
