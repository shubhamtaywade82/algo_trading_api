# frozen_string_literal: true

module Orders
  # Centralized broker order gateway.
  #
  # Responsibility:
  # - enforce PLACE_ORDER feature toggle for all order placement paths
  # - provide a single integration point to DhanHQ order APIs
  class Gateway
    class << self
      # Places a regular order through the broker.
      #
      # @param payload [Hash] broker order payload
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run or :order details
      def place_order(payload, logger: Rails.logger, source: nil)
        return blocked_result(payload, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        order = DhanHQ::Models::Order.new(payload)
        order.save

        {
          dry_run: false,
          order_id: order.order_id || order.id,
          order_status: order.order_status || order.status,
          raw: order
        }
      end

      # Places a super/bracket order through the broker.
      #
      # @param payload [Hash] super-order payload
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run or :order details
      def place_super_order(payload, logger: Rails.logger, source: nil)
        return blocked_result(payload, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        order = DhanHQ::Models::SuperOrder.create(payload)

        {
          dry_run: false,
          order_id: order.order_id || order.id,
          order_status: order.order_status || order.status,
          raw: order
        }
      end

      # Checks whether live order placement is enabled.
      #
      # @param logger [#warn,nil] logger-like object
      # @param source [String,nil] caller identifier for logs
      # @return [Boolean]
      def place_order_enabled?(logger: Rails.logger, source: nil)
        return true if ENV['PLACE_ORDER'] == 'true'

        logger&.warn("[Orders::Gateway] PLACE_ORDER disabled; order blocked#{source_suffix(source)}")
        false
      end

      private

      def blocked_result(payload, logger:, source: nil)
        logger&.info("[Orders::Gateway] blocked payload=#{payload.inspect}#{source_suffix(source)}")
        { dry_run: true, blocked: true, message: 'PLACE_ORDER is not true; order not sent.', payload: payload }
      end

      def source_suffix(source)
        source.present? ? " (source=#{source})" : ''
      end
    end
  end
end
