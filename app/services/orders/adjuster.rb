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
        modification_params = {
          'dhanClientId' => order['dhanClientId'],
          'orderId' => order['orderId'],
          'orderType' => order['orderType'],
          'legName' => order['legName'],
          'quantity' => order['quantity'],
          'price' => order['price'],
          'disclosedQuantity' => order['disclosedQuantity'],
          'triggerPrice' => @new_trigger,
          'validity' => order['validity']
        }.compact

        response = Dhanhq::API::Orders.modify(order_id, modification_params)

        if response['orderStatus'].to_s.upcase.in?(%w[PENDING TRANSIT])
          TelegramNotifier.send_message("🔁 Adjusted SL to ₹#{@new_trigger} for #{@pos['tradingSymbol']}")
          Rails.logger.info("[Orders::Adjuster] SL updated to #{@new_trigger} for #{@pos['tradingSymbol']}")
        else
          Rails.logger.error("[Orders::Adjuster] Modify failed: #{response['omsErrorDescription'] || response['message']}")
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

      # Filter for open/active order status (typically 'PENDING', 'TRANSIT', 'PART_TRADED')
      active_statuses = %w[PENDING TRANSIT PART_TRADED]
      matching = open_orders.find do |o|
        o['securityId'].to_s == @pos['securityId'].to_s &&
          active_statuses.include?(o['orderStatus'])
      end

      matching && matching['orderId']
    end

    def fetch_order_details(order_id)
      # Ideally, there should be an Orders.find(order_id) call.
      # Fallback: get from order list if details API isn't available.
      Dhanhq::API::Orders.list.find { |o| o['orderId'] == order_id }
    end

    def fallback_exit
      TelegramNotifier.send_message("⚠️ SL Adjust failed. Fallback exit initiated for #{@pos['tradingSymbol']}")
      Rails.logger.warn("[Orders::Adjuster] Executing fallback exit for #{@pos['tradingSymbol']}")
      analysis = Orders::Analyzer.call(@pos)
      Orders::Executor.call(@pos, 'FallbackExit', analysis)
    end
  end
end
