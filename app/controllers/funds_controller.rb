class FundsController < ApplicationController
  def index
    funds = FundsService.fetch_funds
    render json: funds.except(:dhanClientId)
  end
end
