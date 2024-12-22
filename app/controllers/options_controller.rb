class OptionsController < ApplicationController
  def suggest_strategies
    index_symbol = params[:index_symbol]
    expiry_date = params[:expiry_date]
    option_preference = params[:option_preference] || "both" # Default to "both"

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

    suggester = Option::StrategySuggester.new(option_chain, params)
    strategies = suggester.suggest(outlook: params[:outlook], volatility: params[:volatility], risk: params[:risk], option_preference: option_preference)

    render json: { index_symbol: index_symbol, strategies: strategies }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
