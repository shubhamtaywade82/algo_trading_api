class StatementsController < ApplicationController
  def ledger
    ledger = StatementsService.fetch_ledger(params[:from_date], params[:to_date])
    render json: ledger
  end

  def trade_history
    history = StatementsService.fetch_trade_history(params[:from_date], params[:to_date], params[:page])
    render json: history
  end
end
