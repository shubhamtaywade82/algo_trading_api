# frozen_string_literal: true

class MarketSentimentController < ApplicationController
  def show
    # 1) Grab the index symbol & expiry from params
    index_symbol = params[:index].to_s.upcase # e.g. 'NIFTY'
    requested_expiry = params[:expiry]

    # 2) Find the instrument in the DB
    instrument = Instrument.segment_index.find_by!(underlying_symbol: index_symbol)
    raise "Instrument not found for #{index_symbol}" unless instrument

    # 3) Determine which expiry to use
    expiry = if requested_expiry.present?
               instrument.expiry_list.find { |e| e == requested_expiry } || instrument.expiry_list.first
             else
               instrument.expiry_list.first
             end

    # 4) Fetch the option chain
    option_chain = instrument.fetch_option_chain(expiry)

    iv_rank = Option::ChainAnalyzer.estimate_iv_rank(option_chain)
    signal_type = resolve_signal_type
    strategy_type = resolve_strategy_type
    historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: strategy_type)

    last_price = instrument.ltp || option_chain[:last_price]
    # 6) Instantiate the new advanced ChainAnalyzer
    chain_analyzer = Option::ChainAnalyzer.new(
      option_chain,
      expiry: expiry,
      underlying_spot: last_price,
      iv_rank: iv_rank,
      historical_data: historical_data
    )
    analysis_result = chain_analyzer.analyze(signal_type: signal_type,
                                             strategy_type: strategy_type)

    # 7) Use the StrategySuggester to generate potential multi-leg strategies
    #    (We can pass user criteria, e.g. :outlook, :risk, etc., if we want.)
    user_criteria = { analysis: analysis_result } # minimal. Or merge in user param filters, e.g. params[:outlook]
    suggester     = Option::StrategySuggester.new(option_chain, last_price, params)
    strategies    = suggester.suggest(user_criteria)

    render json: {
      analysis: analysis_result,           # chain analyzer result
      strategy_suggestions: strategies     # array of possible strategy combos
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private


  def resolve_signal_type
    raw = params[:signal_type].presence || params[:instrument_type].presence
    return :ce unless raw

    normalized = raw.to_s.downcase
    return :pe if normalized.include?('pe') || normalized.include?('put')

    :ce
  end

  def resolve_strategy_type
    params[:strategy_type].presence || 'intraday'
  end
end
