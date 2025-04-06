# frozen_string_literal: true

class OptionsController < ApplicationController
  def index
    strategies = Option::SuggestStrategyService.call(
      index_symbol: strategy_params[:index_symbol],
      expiry_date: strategy_params[:expiry_date],
      params: strategy_params
    )
    render json: { strategies: strategies }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def analysis
    raise "Instrument not found for #{index_symbol}" unless instrument

    option_chain = instrument.fetch_option_chain(expiry_date)
    last_price = instrument.ltp || option_chain[:last_price]

    chain_analyzer = Option::ChainAnalyzer.new(
      option_chain,
      expiry: expiry_date,
      underlying_spot: last_price,
      historical_data: Dhanhq::API::Historical.daily(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        fromDate: 45.days.ago.to_date.to_s,
        toDate: Date.yesterday.to_s
      )
    )
    analysis_result = chain_analyzer.analyze(strategy_type: params[:strategy_type],
                                             instrument_type: params[:instrument_type])

    render json: { analysis: analysis_result }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def expiry_date
    if params[:expiry].present?
      instrument.expiry_list.find { |e| e == params[:expiry] } || instrument.expiry_list.first
    else
      instrument.expiry_list.first
    end
  end

  def instrument
    @instrument ||= Instrument.segment_index.find_by!(underlying_symbol: params[:index].to_s.upcase)
  end

  def strategy_params
    params.require(:option).permit(:index_symbol, :expiry_date, :outlook, :volatility, :risk, :option_preference,
                                   :target_profit, :max_loss, :strategy_type, :instrument_type)
  end
end
