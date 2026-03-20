# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that places a live or dry-run order via Orders::Gateway.
    class PlaceOrder
      extend ExecutionHelpers
      def self.name
        'place_order'
      end

      def self.definition
        {
          name: name,
          title: 'Place Order',
          description: 'Places an order via Orders::Gateway. Actual broker placement requires PLACE_ORDER=true.',
          inputSchema: {
            type: 'object',
            properties: {
              security_id: { type: 'string', description: 'Dhan security ID' },
              exchange_segment: { type: 'string', description: 'e.g. NSE_FNO' },
              transaction_type: { type: 'string', description: 'BUY or SELL' },
              quantity: { type: 'integer', description: 'Order quantity (>=1)' },
              order_type: { type: 'string', description: 'MARKET or LIMIT (default LIMIT)', enum: %w[MARKET LIMIT] },
              product_type: { type: 'string', description: 'INTRADAY | MARGIN | CNC' },
              price: { type: 'number', description: 'Limit price (optional; if omitted, system uses LTP + 0.2% buffer)' },
              max_slippage_percentage: { type: 'number', description: 'Max allowed slippage from LTP (default 0.5%)' }
            },
            required: %w[security_id exchange_segment transaction_type quantity product_type]
          }
        }
      end

      def self.execute(args)
        opts = normalize_args!(name, args).with_indifferent_access
        security_id = opts[:security_id].to_s
        exchange_segment = opts[:exchange_segment].to_s
        transaction_type = opts[:transaction_type].to_s.upcase
        quantity = opts[:quantity].to_i
        product_type = opts[:product_type].to_s
        order_type = opts[:order_type].presence&.upcase || 'LIMIT'
        price = opts[:price]

        validate!(security_id: security_id, exchange_segment: exchange_segment, transaction_type: transaction_type, quantity: quantity, product_type: product_type, order_type: order_type, price: price)

        payload = build_payload(
          security_id: security_id,
          exchange_segment: exchange_segment,
          transaction_type: transaction_type,
          quantity: quantity,
          product_type: product_type,
          order_type: order_type,
          price: price
        )

        Orders::Manager.place_order(payload, source: 'mcp_place_order')
          .slice(:dry_run, :blocked, :message, :order_id, :order_status, :payload)
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def validate!(security_id:, exchange_segment:, transaction_type:, quantity:, product_type:, order_type:, price:)
          raise ArgumentError, 'security_id is required' if security_id.blank?
          raise ArgumentError, 'exchange_segment is required' if exchange_segment.blank?
          raise ArgumentError, 'transaction_type must be BUY or SELL' unless %w[BUY SELL].include?(transaction_type)
          raise ArgumentError, 'quantity must be >= 1' if quantity < 1
          raise ArgumentError, 'product_type is required' if product_type.blank?
          raise ArgumentError, 'order_type must be MARKET or LIMIT' unless %w[MARKET LIMIT].include?(order_type)

          if order_type == 'LIMIT' && (price.nil? || price.to_f <= 0)
            raise ArgumentError, 'price is required and must be > 0 for LIMIT orders'
          end
        end

        def build_payload(security_id:, exchange_segment:, transaction_type:, quantity:, product_type:, order_type:, price:)
          payload = {
            security_id: security_id.to_i,
            exchange_segment: exchange_segment,
            transaction_type: transaction_type,
            quantity: quantity,
            product_type: product_type,
            order_type: order_type,
            validity: 'DAY'
          }
          payload[:price] = price.to_f if order_type == 'LIMIT'
          payload
        end
      end
    end
  end
end

