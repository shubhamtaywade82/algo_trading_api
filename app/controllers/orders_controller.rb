# frozen_string_literal: true

class OrdersController < ApplicationController
  def index
    orders = OrdersService.fetch_orders
    render json: orders
  end

  def trades
    trades = OrdersService.fetch_trades
    render json: trades
  end
end
