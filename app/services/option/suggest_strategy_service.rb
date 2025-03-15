# frozen_string_literal: true

module Option
  class SuggestStrategyService
    def self.call(index_symbol:, expiry_date:, params:)
      # 1) Find the instrument by index_symbol (NIFTY, BANKNIFTY, etc.)
      instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol)
      Rails.logger.debug { "Found instrument => #{instrument}" }
      raise "Invalid index symbol: #{index_symbol}" unless instrument

      # 2) Determine which expiry to use
      expiry = instrument.expiry_list.find { |e| e == expiry_date } || instrument.expiry_list.first

      # 3) Fetch real-time option chain for that expiry
      option_chain = instrument.fetch_option_chain(expiry)

      # 4) Optionally fetch short historical data (daily bars for the last ~5 days)
      historical_data = fetch_historical_data(instrument)

      # 5) Instantiate the new Option::ChainAnalyzer with advanced logic
      chain_analyzer = Option::ChainAnalyzer.new(
        option_chain,
        expiry: expiry,
        underlying_spot: instrument.ltp,         # pass the real-time spot
        historical_data: historical_data         # pass short daily bars
      )

      # 6) Run the analyzer to get advanced insights
      analysis = chain_analyzer.analyze(strategy_type: params[:strategy_type], instrument_type: params[:instrument_type])
      # => {
      #      atm_strike: 22550,
      #      best_ce_strike: {...},
      #      best_pe_strike: {...},
      #      trend: "neutral" / "bullish" / "bearish",
      #      volatility: { average_iv: 22.5, high_volatility: true },
      #      greeks_summary: {...}
      #    }

      # 7) Instantiate the StrategySuggester with the chain data + user params
      suggester = StrategySuggester.new(option_chain, params)

      # 8) Suggester uses “analysis” (plus any user’s input like :outlook, :risk, etc.)
      #    to produce an array of strategies. We return the final suggestions.
      suggester.suggest(analysis: analysis)
    end

    def self.fetch_historical_data(instrument)
      # Basic daily data for the last 5 days, ignoring weekends
      Dhanhq::API::Historical.daily(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument_type,
        fromDate: 45.days.ago.to_date.to_s,
        toDate: Date.yesterday.to_s
      )
    rescue StandardError
      []
    end
  end
end
