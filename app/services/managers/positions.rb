# frozen_string_literal: true

module Positions
  class Manager < Managers::Base
    def call
      execute_safely do
        manage_positions
        adjust_stop_loss_for_positions
      end
    end

    private

    def manage_positions
      Position.open.each do |position|
        close_position_if_profitable(position)
      end
    end

    def close_position_if_profitable(position)
      if profitable?(position)
        close_position(position)
      else
        log_info("Position not profitable: #{position.id}")
      end
    end

    def profitable?(position)
      position.unrealized_profit >= position.entry_price * 0.02 # Example: 2% profit threshold
    end

    def close_position(position)
      response = Dhanhq::API::Orders.place(close_order_params(position))
      if response['status'] == 'success'
        position.update(status: :closed)
        log_info("Position closed: #{position.id}")
      else
        log_error("Failed to close position: #{position.id}")
      end
    end

    def close_order_params(position)
      {
        transactionType: position.position_type == 'LONG' ? 'SELL' : 'BUY',
        orderType: 'MARKET',
        productType: position.product_type,
        securityId: position.security_id,
        quantity: position.net_qty
      }
    end

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

    def trail_stop_loss_for_positions
      Position.open.each do |position|
        new_stop_loss = calculate_trailing_stop_loss(position)
        update_stop_loss(position, new_stop_loss) if new_stop_loss != position.stop_loss_price
      end
    end

    def calculate_trailing_stop_loss(position)
      entry_price = position.entry_price
      current_price = position.current_market_price
      trailing_amount = position.trailing_stop_loss

      return position.stop_loss_price if current_price <= entry_price

      if position.position_type == 'LONG'
        current_price - trailing_amount
      else
        current_price + trailing_amount
      end.round(2)
    end
  end
end
