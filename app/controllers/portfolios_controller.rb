# frozen_string_literal: true

class PortfoliosController < ApplicationController
  def holdings
    holdings = PortfolioService.fetch_holdings
    render json: holdings
  end

  def positions
    positions = PortfolioService.fetch_positions
    render json: positions
  end
end
