# frozen_string_literal: true

module Managers
  class Orders < Base
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
      { error: e.message }
    end

    def process_pending_orders
      orders = fetch_orders.select { |order| %w[PENDING TRANSIT].include?(order['orderStatus']) }

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

      response = Dhanhq::API::Orders.modify(
        order_id: order['orderId'],
        price: target_profit,
        stop_loss_price: stop_loss
      )
      if response['status'] == 'success'
        log_info("Updated stop-loss and target price for order #{order['orderId']}")
      else
        log_error("Failed to update order #{order['orderId']}: #{response['omsErrorDescription']}")
      end
    end

    def calculate_target_profit(order)
      entry_price = order['price'].to_f
      (entry_price * 1.02).round(2) # 2% target profit
    end

    def calculate_stop_loss(order)
      entry_price = order['price'].to_f
      (entry_price * 0.98).round(2) # 2% stop loss
    end
  end
end
