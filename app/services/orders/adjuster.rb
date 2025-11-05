# frozen_string_literal: true

# Modifies the SL leg of an existing bracket or SL order, fallback to exit if needed
module Orders
  class Adjuster < ApplicationService
    # @param [Hash] position
    # @param [Hash] params (expects :trigger_price)
    def initialize(position, params)
      @pos         = position.with_indifferent_access
      @new_trigger = params[:trigger_price]
    end

    def call
      order_id = find_active_order_id

      if order_id
        order = fetch_order_details(order_id)
        unless order
          Rails.logger.error("[Orders::Adjuster] Could not find order details for #{order_id}")
          return fallback_exit
        end

        # Prepare modification params as per Dhan API doc
        order_obj = DhanHQ::Models::Order.find(order_id)
        return fallback_exit unless order_obj

        # Use order.modify method from new gem
        order_obj.modify(trigger_price: @new_trigger)
        order_status = order_obj.order_status || order_obj.status

        if order_status.to_s.upcase.in?(%w[PENDING TRANSIT])
          notify("🔁 Adjusted SL to ₹#{@new_trigger} for #{@pos['tradingSymbol']}")
          Rails.logger.info("[Orders::Adjuster] SL updated to #{@new_trigger} for #{@pos['tradingSymbol']}")
        else
          Rails.logger.error("[Orders::Adjuster] Modify failed: #{order_obj.errors.full_messages.join(', ')}")
          fallback_exit
        end
      else
        Rails.logger.warn("[Orders::Adjuster] No active order to modify for #{@pos['tradingSymbol']}")
        fallback_exit
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Adjuster] Error adjusting SL for #{@pos['tradingSymbol']}: #{e.message}")
      fallback_exit
    end

    private

    def find_active_order_id
      open_orders = DhanHQ::Models::Order.all

      # Filter for open/active order status (typically 'PENDING', 'TRANSIT', 'PART_TRADED')
      active_statuses = %w[PENDING TRANSIT PART_TRADED]
      security_id = @pos['securityId'] || @pos[:security_id]
      matching = open_orders.find do |o|
        o_hash = o.is_a?(Hash) ? o : o.to_h
        o_security_id = o_hash['securityId'] || o_hash[:security_id] || o_hash['security_id']
        o_status = o_hash['orderStatus'] || o_hash[:order_status] || o_hash['order_status']
        o_security_id.to_s == security_id.to_s &&
          active_statuses.include?(o_status.to_s)
      end

      return unless matching

      matching.is_a?(Hash) ? (matching['orderId'] || matching[:order_id]) : (matching.order_id || matching.id)
    end

    def fetch_order_details(order_id)
      # Find order from all orders
      order = DhanHQ::Models::Order.all.find do |o|
        (o.is_a?(Hash) ? (o['orderId'] || o[:order_id]) : (o.order_id || o.id)).to_s == order_id.to_s
      end
      order.is_a?(Hash) ? order : order.to_h
    end

    def fallback_exit
      notify("⚠️ SL Adjust failed. Fallback exit initiated for #{@pos['tradingSymbol']}")
      Rails.logger.warn("[Orders::Adjuster] Executing fallback exit for #{@pos['tradingSymbol']}")
      analysis = Orders::Analyzer.call(@pos)
      Orders::Executor.call(@pos, 'FallbackExit', analysis)
    end
  end
end
