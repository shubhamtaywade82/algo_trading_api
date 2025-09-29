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
    raise "Instrument not found for #{params[:index]}" unless instrument

    option_chain = instrument.fetch_option_chain(expiry_date)
    last_price = instrument.ltp || option_chain[:last_price]

    iv_rank = calculate_iv_rank(option_chain)
    strategy_type = params[:strategy_type].presence || 'intraday'
    historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: strategy_type)

    chain_analyzer = Option::ChainAnalyzer.new(
      option_chain,
      expiry: expiry_date,
      underlying_spot: last_price,
      iv_rank: iv_rank,
      historical_data: historical_data
    )

    signal_type = params[:instrument_type].to_s.downcase.to_sym # :ce or :pe

    result = chain_analyzer.analyze(
      strategy_type: strategy_type,
      signal_type: signal_type
    )

    render json: { result: result }, status: :ok
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
    permitted = params.require(:option).permit(:index_symbol, :expiry_date, :outlook, :volatility, :risk,
                                               :option_preference, :target_profit, :max_loss, :strategy_type,
                                               :instrument_type, :instrument_typs)

    if permitted[:instrument_type].blank? && permitted[:instrument_typs].present?
      permitted[:instrument_type] = permitted.delete(:instrument_typs)
    else
      permitted.delete(:instrument_typs)
    end

    permitted
  end

  def calculate_iv_rank(option_chain)
    Option::ChainAnalyzer.estimate_iv_rank(option_chain)
  end
end
