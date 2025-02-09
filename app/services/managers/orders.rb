# frozen_string_literal: true

module Managers
  class Orders < Base
    STATUSES = %w[PENDING TRANSIT].freeze

    def call
      log_info("Orders Manager called at #{Time.zone.now}")

      execute_safely do
        process_pending_orders
        monitor_open_orders
      end
    end

    private

    def fetch_orders
      Dhanhq::API::Orders.list
    rescue StandardError => e
      log_error('Error fetching orders', e)
      []
    end

    def process_pending_orders
      orders = fetch_orders.select { |order| STATUSES.include?(order['orderStatus']) }

      orders.each do |order|
        execute_safely do
          valid_order?(order) ? attempt_order_placement(order) : cancel_order(order)
        end
      end
    end

    def monitor_open_orders
      fetch_orders.select { |order| order['orderStatus'] == 'TRADED' }.each do |order|
        evaluate_and_update_stop_loss(order)
      end
    end

    def evaluate_and_update_stop_loss(order)
      modify_params = {
        price: calculate_target_profit(order),
        triggerPrice: calculate_stop_loss(order) # Stop-loss is set via `triggerPrice`
      }

      response = Dhanhq::API::Orders.modify(order['orderId'], modify_params)

      if response['status'] == 'success'
        log_info("Stop-loss & target price updated for order #{order['orderId']}")
      else
        log_error("Failed to update order #{order['orderId']}", response['omsErrorDescription'])
      end
    end

    def calculate_target_profit(order)
      (order['price'].to_f * 1.02).round(2) # 2% target profit
    end

    def calculate_stop_loss(order)
      (order['price'].to_f * 0.98).round(2) # 2% stop loss
    end

    def valid_order?(order)
      order['quantity'].to_i.positive? && order['price'].to_f.positive?
    end

    def attempt_order_placement(order)
      response = Dhanhq::API::Orders.place(build_order_params(order))
      response['status'] == 'success' ? log_info("🎯 Order placed: #{order['orderId']}") : log_error("Order failed: #{order['orderId']}")
    end

    def build_order_params(order)
      {
        transactionType: order['transactionType'],
        exchangeSegment: order['exchangeSegment'],
        productType: order['productType'],
        orderType: order['orderType'],
        securityId: order['securityId'],
        quantity: order['quantity'],
        price: order['price']
      }
    end

    def cancel_order(order)
      response = Dhanhq::API::Orders.cancel(order['orderId'])
      response['status'] == 'success' ? log_info("Order cancelled: #{order['orderId']}") : log_error("Failed to cancel order #{order['orderId']}")
    end
  end
end
