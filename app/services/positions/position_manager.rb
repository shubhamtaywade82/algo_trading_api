# frozen_string_literal: true

module Positions
  class PositionManager < ApplicationService
    def call
      open_positions = fetch_open_positions
      open_positions.each do |position|
        Orders::OrderManager.close_position(position) if unrealized_profit_met?(position)
      end
    end

    private

    def fetch_open_positions
      Dhanhq::API::Portfolio.positions
    end

    def unrealized_profit_met?(position)
      position['unrealizedProfit'].to_f >= (position['costPrice'].to_f * 1.02)
    end
  end
end
