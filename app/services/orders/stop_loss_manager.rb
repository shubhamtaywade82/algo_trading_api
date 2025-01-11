# frozen_string_literal: true

module Orders
  class StopLossManager < ApplicationService
    def initialize(order, market_price)
      @order = order
      @market_price = market_price
    end

    def call
      new_stop_loss = calculate_stop_loss
      update_order_stop_loss(new_stop_loss)
    rescue StandardError => e
      Rails.logger.error("Failed to update stop-loss: #{e.message}")
    end

    private

    def calculate_stop_loss
      (@market_price * 0.98).round(2) # 2% below current market price
    end

    def update_order_stop_loss(new_stop_loss)
      response = Dhanhq::API::Orders.modify(order_id: @order.id, stop_loss_price: new_stop_loss)
      raise "Failed to update stop-loss: #{response['error']}" unless response['status'] == 'success'
    end
  end
end
