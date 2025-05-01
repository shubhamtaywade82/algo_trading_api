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

    chain_analyzer = Option::ChainAnalyzer.new(
      option_chain,
      expiry: expiry_date,
      underlying_spot: last_price,
      iv_rank: iv_rank,
      historical_data: Dhanhq::API::Historical.daily(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        fromDate: 45.days.ago.to_date.to_s,
        toDate: Date.yesterday.to_s
      )
    )

    signal_type = params[:instrument_type].to_s.downcase.to_sym # :ce or :pe

    result = chain_analyzer.analyze(
      strategy_type: params[:strategy_type] || 'intraday',
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
    params.require(:option).permit(:index_symbol, :expiry_date, :outlook, :volatility, :risk, :option_preference,
                                   :target_profit, :max_loss, :strategy_type, :instrument_type)
  end

  def calculate_iv_rank(option_chain)
    atm_strike = option_chain[:last_price].to_f
    atm_key = format('%.6f', atm_strike)

    ce_iv = option_chain.dig(:oc, atm_key, 'ce', 'implied_volatility').to_f
    pe_iv = option_chain.dig(:oc, atm_key, 'pe', 'implied_volatility').to_f
    current_iv = [ce_iv, pe_iv].compact.sum / 2.0

    all_ivs = option_chain[:oc].values.flat_map do |row|
      [row.dig('ce', 'implied_volatility'), row.dig('pe', 'implied_volatility')]
    end.compact.map(&:to_f)

    return 0.5 if all_ivs.empty? || all_ivs.uniq.size == 1

    min_iv = all_ivs.min
    max_iv = all_ivs.max
    ((current_iv - min_iv) / (max_iv - min_iv)).clamp(0.0, 1.0).round(2)
  end
end
