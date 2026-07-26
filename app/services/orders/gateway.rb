# frozen_string_literal: true

module Orders
  # Centralized broker order gateway.
  #
  # Responsibility:
  # - enforce PLACE_ORDER feature toggle for all order placement paths
  # - provide a single integration point to DhanHQ order APIs
  #
  # Two independent switches must both be on for an order to reach the broker:
  #
  # - `PLACE_ORDER` — this application's gate, checked here.
  # - `LIVE_TRADING` — DhanHQ >= 2.7's own gate. The SDK raises
  #   `DhanHQ::LiveTradingDisabledError` from inside `Order#save` /
  #   `SuperOrder.create` when it is not exactly "true".
  #
  # We check the SDK's switch here as well so a misconfigured deployment gets
  # the same structured dry-run result as `PLACE_ORDER=false`, instead of an
  # exception raised from deep in the gem on the first live signal.
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
      # Requires both this app's `PLACE_ORDER` toggle and the SDK's own
      # `LIVE_TRADING` toggle.
      #
      # @param logger [#warn,nil] logger-like object
      # @param source [String,nil] caller identifier for logs
      # @return [Boolean]
      def place_order_enabled?(logger: Rails.logger, source: nil)
        blocked_reason(logger: logger, source: source).nil?
      end

      private

      # @return [String, nil] why placement is blocked, or nil when allowed
      def blocked_reason(logger: Rails.logger, source: nil)
        if ENV['PLACE_ORDER'] != 'true'
          logger&.warn("[Orders::Gateway] PLACE_ORDER disabled; order blocked#{source_suffix(source)}")
          return 'PLACE_ORDER is not true; order not sent.'
        end

        # DhanHQ >= 2.7 refuses every order mutation without this.
        if ENV['LIVE_TRADING'] != 'true'
          logger&.warn("[Orders::Gateway] LIVE_TRADING disabled; order blocked#{source_suffix(source)}")
          return 'LIVE_TRADING is not true; DhanHQ SDK would reject this order.'
        end

        nil
      end

      def blocked_result(payload, logger:, source: nil)
        reason = blocked_reason(logger: nil, source: source) || 'order not sent.'
        logger&.info("[Orders::Gateway] blocked payload=#{payload.inspect}#{source_suffix(source)}")
        { dry_run: true, blocked: true, message: reason, payload: payload }
      end

      def source_suffix(source)
        source.present? ? " (source=#{source})" : ''
      end
    end
  end
end
