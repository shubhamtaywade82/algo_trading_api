class OptionsController < ApplicationController
  def suggest_strategies
    index_symbol = params[:index_symbol]
    expiry_date = params[:expiry_date]
    option_preference = params[:option_preference] || "both"

    # Fetch instrument data
    instrument = Instrument.indices.find_by(underlying_symbol: index_symbol, segment: "I")
    if instrument.nil?
      return render json: { error: "Invalid index symbol." }, status: :unprocessable_entity
    end

    # Fetch option chain using Dhanhq::API::Option
    option_chain = Dhanhq::API::Option.chain(
      UnderlyingScrip: instrument.security_id,
      UnderlyingSeg: instrument.exchange_segment,
      Expiry: expiry_date
    )

    # Analyze the options chain
    analysis = Option::ChainAnalyzer.new(option_chain).analyze

    # Suggest strategies based on analysis
    suggester = Option::StrategySuggester.new(option_chain, params)
    strategies = suggester.suggest(
      analysis: analysis,
      option_preference: option_preference,
      outlook: params[:outlook],
      volatility: params[:volatility],
      risk: params[:risk]
    )

    render json: { index_symbol: index_symbol, strategies: strategies, analysis: analysis }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
