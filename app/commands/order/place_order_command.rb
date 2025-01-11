# frozen_string_literal: true

module Order
  class PlaceOrderCommand < ApplicationService
    def initialize(order_params)
      @order_params = order_params
    end

    def call
      response = Dhanhq::API::Orders.place(@order_params)
      raise "Order placement failed: #{response['error']}" unless response['status'] == 'success'

      Order.create!(response.slice('orderId', 'status', 'quantity', 'price'))
    rescue StandardError => e
      Rails.logger.error("Failed to place order: #{e.message}")
      raise
    end
  end
end
