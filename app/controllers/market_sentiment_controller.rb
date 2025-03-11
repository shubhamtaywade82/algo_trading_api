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

    # 5) Optionally fetch short historical data for chain analysis
    historical_data = fetch_short_historical_data(instrument)

    # 6) Instantiate the new advanced ChainAnalyzer
    chain_analyzer = Option::ChainAnalyzer.new(
      option_chain,
      expiry: expiry,
      underlying_spot: instrument.ltp,
      historical_data: historical_data
    )
    analysis_result = chain_analyzer.analyze(strategy_type: params[:strategy_type], instrument_type: params[:instrument_type])

    # 7) Use the StrategySuggester to generate potential multi-leg strategies
    #    (We can pass user criteria, e.g. :outlook, :risk, etc., if we want.)
    user_criteria = { analysis: analysis_result } # minimal. Or merge in user param filters, e.g. params[:outlook]
    suggester     = Option::StrategySuggester.new(option_chain, params)
    strategies    = suggester.suggest(user_criteria)

    render json: {
      analysis: analysis_result,           # chain analyzer result
      strategy_suggestions: strategies     # array of possible strategy combos
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Example: fetch 5 days of daily candles
  def fetch_short_historical_data(instrument)
    Dhanhq::API::Historical.daily(
      securityId: instrument.security_id,
      exchangeSegment: instrument.exchange_segment,
      instrument: instrument.instrument_type,
      fromDate: 5.days.ago.to_date.to_s,
      toDate: Date.yesterday.to_s
    )
  rescue StandardError
    []
  end
end
