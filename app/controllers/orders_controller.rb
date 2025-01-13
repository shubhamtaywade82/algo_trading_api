# frozen_string_literal: true

class OrdersController < ApplicationController
  def index
    orders = OrdersService.fetch_orders
    render json: ResponseHelper.success_response(orders)
  rescue StandardError => e
    render json: ResponseHelper.error_response(e.message), status: :unprocessable_entity
  end

  def trades
    trades = OrdersService.fetch_trades
    render json: trades
  end
end
