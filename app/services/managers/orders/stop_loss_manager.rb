# frozen_string_literal: true

module Managers
  module Orders
    class StopLossManager < Managers::Base
      def initialize(order, market_price)
        @order = order
        @market_price = market_price
      end

      def call
        execute_safely do
          adjust_stop_loss
        end
      end

      private

      def adjust_stop_loss
        new_stop_loss = calculate_new_stop_loss
        if new_stop_loss == @order.stop_loss_price
          log_info("No adjustment needed for order #{@order.id}")
        else
          update_stop_loss_order(new_stop_loss)
        end
      end

      def calculate_new_stop_loss
        (@market_price * 0.98).round(2) # Adjust to 2% below the current market price
      end

      def update_stop_loss_order(new_stop_loss)
        response = Dhanhq::API::Orders.modify(order_id: @order.dhan_order_id, stop_loss_price: new_stop_loss)
        if response['status'] == 'success'
          @order.update(stop_loss_price: new_stop_loss)
          log_info("Stop-loss updated for order #{@order.id} to #{new_stop_loss}")
        else
          log_error("Failed to update stop-loss for order #{@order.id}", response['error'])
        end
      end
    end
  end
end
