class OptionsController < ApplicationController
  def suggest_strategies
    strategies = Option::SuggestStrategyService.call(
      index_symbol: params[:index_symbol],
      expiry_date: params[:expiry_date],
      params: params
    )
    render json: { strategies: strategies }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
