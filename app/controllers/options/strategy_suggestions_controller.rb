# frozen_string_literal: true

module Options
  class StrategySuggestionsController < ApplicationController
    def index
      strategies = Option::SuggestStrategyService.call(
        index_symbol: strategy_params[:index_symbol],
        expiry_date: strategy_params[:expiry_date],
        params: strategy_params
      )
      render json: strategies
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def strategy_params
      params.require(:option).permit(:index_symbol, :expiry_date, :outlook, :volatility, :risk, :option_preference,
                                     :target_profit, :max_loss)
    end
  end
end
