# frozen_string_literal: true

class FundsController < ApplicationController
  def index
    funds = FundsService.fetch_funds
    render json: funds.except(:dhanClientId)
  rescue StandardError => e
    render json: ErrorHandler.handle_error(
      context: 'FundsController#index',
      exception: e
    ), status: :unprocessable_entity
  end
end
