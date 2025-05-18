# frozen_string_literal: true

module Orders
  class Adjuster < ApplicationService
    def initialize(position, params)
      @pos          = position.with_indifferent_access
      @new_trigger  = params[:trigger_price]
    end

    def call
      order_id = find_active_order_id

      if order_id
        response = Dhanhq::API::Orders.modify(order_id, { triggerPrice: @new_trigger })

        if response['status'] == 'success'
          TelegramNotifier.send_message("🔁 Adjusted SL to ₹#{@new_trigger} for #{@pos['tradingSymbol']}")
          Rails.logger.info("[Orders::Adjuster] SL updated to #{@new_trigger} for #{@pos['tradingSymbol']}")
        else
          Rails.logger.error("[Orders::Adjuster] Modify failed: #{response['omsErrorDescription']}")
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
      open_orders = Dhanhq::API::Orders.list
      # Filter for open/active order status (typically 'PENDING', 'TRANSIT', etc.)
      active_statuses = %w[PENDING TRANSIT PART_TRADED]
      matching = open_orders.find do |o|
        o['securityId'].to_s == @pos['securityId'].to_s &&
          active_statuses.include?(o['orderStatus'])
      end
      matching && matching['orderId']
    end

    def fallback_exit
      TelegramNotifier.send_message("⚠️ SL Adjust failed. Fallback exit initiated for #{@pos['tradingSymbol']}")
      Rails.logger.warn("[Orders::Adjuster] Executing fallback exit for #{@pos['tradingSymbol']}")
      analysis = Orders::Analyzer.call(@pos)
      Orders::Executor.call(@pos, 'FallbackExit', analysis)
    end
  end
end
