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
          if valid_order?(order)
            attempt_order_placement(order)
          else
            cancel_order(order)
          end
        rescue StandardError => e
          log_error("Failed to process order #{order['orderId']}", e)
        end
      end
    end

    def monitor_open_orders
      orders = fetch_orders.select { |order| order['orderStatus'] == 'TRADED' }
      orders.each do |order|
        evaluate_and_update_stop_loss(order)
      end
    end

    def evaluate_and_update_stop_loss(order)
      target_profit = calculate_target_profit(order)
      stop_loss = calculate_stop_loss(order)

      return unless target_profit && stop_loss

      modify_params = {
        price: target_profit,
        triggerPrice: stop_loss # Stop-loss is set via `triggerPrice`
      }

      response = Dhanhq::API::Orders.modify(order['orderId'], modify_params)
      if response['status'] == 'success'
        log_info("Updated stop-loss and target price for order #{order['orderId']}")
      else
        log_error("Failed to update order #{order['orderId']}: #{response['omsErrorDescription']}")
      end
    rescue StandardError => e
      log_error("Error updating order #{order['orderId']}", e)
    end

    def calculate_target_profit(order)
      entry_price = order['price'].to_f
      (entry_price * 1.02).round(2) # 2% target profit
    end

    def calculate_stop_loss(order)
      entry_price = order['price'].to_f
      (entry_price * 0.98).round(2) # 2% stop loss
    end

    def valid_order?(order)
      order['quantity'].to_i.positive? && order['price'].to_f.positive?
    end

    def attempt_order_placement(order)
      response = Dhanhq::API::Orders.place(build_order_params(order))
      if response['status'] == 'success'
        log_info("Order successfully placed: #{order['orderId']}")
      else
        log_error("Order placement failed: #{order['orderId']}, Error: #{response['error']}")
      end
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
      if response['status'] == 'success'
        log_info("Order cancelled: #{order['orderId']}")
      else
        log_error("Failed to cancel order: #{order['orderId']}, Error: #{response['error']}")
      end
    rescue StandardError => e
      log_error("Error cancelling order #{order['orderId']}", e)
    end
  end
end
