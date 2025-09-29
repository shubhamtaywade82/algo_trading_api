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

    strategy_type = resolve_strategy_type
    iv_rank = Option::ChainAnalyzer.estimate_iv_rank(option_chain)
    historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: strategy_type)
    last_price = instrument.ltp || option_chain[:last_price]

    sentiment = Market::SentimentAnalysis.call(
      option_chain: option_chain,
      expiry: expiry,
      spot: last_price,
      iv_rank: iv_rank,
      historical_data: historical_data,
      strategy_type: strategy_type
    )

    preferred_analysis =
      case sentiment[:preferred_signal]
      when :ce then sentiment[:call_analysis]
      when :pe then sentiment[:put_analysis]
      end
    preferred_analysis ||= sentiment[:call_analysis] if sentiment[:call_analysis]&.any?
    preferred_analysis ||= sentiment[:put_analysis] if sentiment[:put_analysis]&.any?

    user_criteria = { analysis: preferred_analysis }
    suggester     = Option::StrategySuggester.new(option_chain, last_price, params)
    strategies    = preferred_analysis ? suggester.suggest(user_criteria) : []

    render json: {
      sentiment: sentiment.slice(:bias, :preferred_signal, :confidence, :trend, :iv_rank, :strengths, :ta_snapshot),
      analyses: {
        call: sentiment[:call_analysis],
        put: sentiment[:put_analysis]
      },
      strategy_suggestions: strategies
    }, status: :ok
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private


  def resolve_strategy_type
    params[:strategy_type].presence || 'intraday'
  end
end
