class OptionsController < ApplicationController
  def suggest_strategies
    index_symbol = params[:index_symbol]
    index_data = Dhanhq::API::OptionsChain.fetch(index_symbol)

    suggester = Options::StrategySuggester.new(index_data, params)
    strategies = suggester.suggest

    render json: { index_symbol: index_symbol, strategies: strategies }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
