# frozen_string_literal: true

module Managers
  module Positions
    class AdjustStopLossManager < Managers::Base
      def call
        execute_safely do
          adjust_stop_loss_for_positions
        end
      end

      private

      def adjust_stop_loss_for_positions
        Position.open.each do |position|
          adjust_stop_loss_for_position(position)
        end
      end

      def adjust_stop_loss_for_position(position)
        new_stop_loss = calculate_new_stop_loss(position)
        if new_stop_loss > position.stop_loss_price
          update_stop_loss(position, new_stop_loss)
        else
          log_info("No adjustment needed for position #{position.id}")
        end
      end

      def calculate_new_stop_loss(position)
        current_price = position.current_market_price
        trailing_amount = position.trailing_stop_loss

        if position.position_type == 'LONG'
          [current_price - trailing_amount, position.stop_loss_price].max
        else
          [current_price + trailing_amount, position.stop_loss_price].min
        end.round(2)
      end

      def update_stop_loss(position, new_stop_loss)
        response = Dhanhq::API::Orders.modify(
          order_id: position.order_id,
          stop_loss_price: new_stop_loss
        )
        if response['status'] == 'success'
          position.update(stop_loss_price: new_stop_loss)
          log_info("Stop-loss updated for position #{position.id} to #{new_stop_loss}")
        else
          log_error("Failed to update stop-loss for position #{position.id}", response['error'])
        end
      end
    end
  end
end
