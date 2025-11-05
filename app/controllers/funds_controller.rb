# frozen_string_literal: true

class FundsController < ApplicationController
  def index
    funds = DhanHQ::Models::Funds.fetch
    funds_hash = funds.to_h.except(:dhan_client_id, 'dhan_client_id')
    render json: funds_hash
  rescue StandardError => e
    render json: ErrorHandler.handle_error(
      context: 'FundsController#index',
      exception: e
    ), status: :unprocessable_entity
  end
end
