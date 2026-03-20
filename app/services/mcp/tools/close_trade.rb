# frozen_string_literal: true

module Mcp
  module Tools
    # Tool for closing an open position on DhanHQ via MCP.
    class CloseTrade
      extend ExecutionHelpers
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
        return { error: 'Dhan not configured. Set DHAN_CLIENT_ID and complete login.' } unless dhan_configured?

        opts = normalize_args!(name, args).with_indifferent_access
        payload = build_payload(opts)

        place_order(payload)
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def dhan_configured?
          ENV['DHAN_CLIENT_ID'].present? || ENV['CLIENT_ID'].present?
        end

        def build_payload(opts)
          net_qty = opts[:net_quantity].to_i
          transaction_type = resolve_transaction_type(opts[:transaction_type], net_qty)

          {
            security_id: opts[:security_id].to_s.to_i,
            exchange_segment: opts[:exchange_segment].to_s,
            transaction_type: transaction_type,
            quantity: net_qty.abs,
            order_type: 'MARKET',
            product_type: opts[:product_type].to_s,
            validity: 'DAY'
          }
        end

        def resolve_transaction_type(type, net_qty)
          parsed_type = type.to_s.upcase
          return parsed_type if parsed_type.present?

          net_qty.positive? ? 'SELL' : 'BUY'
        end

        def place_order(payload)
          Orders::Gateway.place_order(payload, source: name).slice(:dry_run, :message, :order_id, :order_status, :payload)
        end
      end
    end
  end
end
