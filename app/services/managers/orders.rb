# frozen_string_literal: true

module Managers
  class Orders < Base
    def call
      execute_safely do
        process_pending_orders
      end
    end

    def fetch_orders
      execute_safely do
        Dhanhq::API::Orders.list
      rescue StandardError => e
        log_error('Error fetching orders', e)
        { error: e.message }
      end
    end

    def fetch_trades
      execute_safely do
        Dhanhq::API::Orders.trades
      rescue StandardError => e
        log_error('Error fetching trades', e)
        { error: e.message }
      end
    end

    def place_order(ticker:, action:, quantity:, price:, security_id:, trailing_stop_loss: nil)
      execute_safely do
        order_data = {
          transactionType: action.upcase,
          exchangeSegment: 'NSE_EQ',
          productType: 'CNC',
          orderType: 'MARKET',
          securityId: security_id,
          quantity: quantity,
          price: price
        }
        if ENV['PLACE_ORDER'] == 'true'
          response = Dhanhq::API::Orders.place(order_data)

          Order.create(
            ticker: ticker,
            action: action,
            quantity: quantity,
            price: price,
            dhan_order_id: response['orderId'],
            dhan_status: response['orderStatus'],
            security_id: security_id,
            stop_loss_price: calculate_stop_loss(price, action, trailing_stop_loss),
            take_profit_price: calculate_take_profit(price)
          )
        else
          Rails.logger.info("PLACE_ORDER is disabled. Order parameters: #{order_data}")
        end
      rescue StandardError => e
        log_error('Failed to place order', e)
        raise
      end
    end

    def calculate_stop_loss(price, action, trailing_stop_loss)
      return unless trailing_stop_loss

      action == 'BUY' ? price - trailing_stop_loss : price + trailing_stop_loss
    end

    private

    def process_pending_orders
      Order.where(order_status: %w[pending transit]).find_each do |order|
        if order.valid?
          place_order(order)
        else
          cancel_order(order)
        end
      rescue StandardError => e
        log_error("Failed to process order #{order.id}", e)
      end
    end

    def place_order(order)
      response = Dhanhq::API::Orders.place(order.to_api_params)
      if response['status'] == 'success'
        order.update(
          order_status: :traded,
          dhan_order_id: response['orderId'],
          traded_quantity: response['data']&.[]('tradedQuantity'),
          traded_price: response['data']&.[]('tradedPrice')
        )
        log_info("Order placed successfully: #{order.id}")
      else
        order.update(order_status: :failed, error_message: response['error'])
        log_error("Failed to place order: #{order.id}", response['error'])
      end
    rescue StandardError => e
      log_error("Error placing order #{order.id}", e)
    end

    def cancel_order(order)
      order.update(order_status: :cancelled)
      log_info("Order cancelled: #{order.id}")
    end

    def update_order_status(order)
      response = Dhanhq::API::Orders.status(order.dhan_order_id)
      return unless response['status'] == 'success'

      order.update(
        order_status: response['data']['status'],
        traded_quantity: response['data']['tradedQuantity'],
        traded_price: response['data']['tradedPrice']
      )
      log_info("Order status updated for #{order.id}")
    rescue StandardError => e
      log_error("Failed to update order status for #{order.dhan_order_id}", e)
    end
  end
end
