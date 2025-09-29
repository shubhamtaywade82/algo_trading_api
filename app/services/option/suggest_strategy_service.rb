# frozen_string_literal: true

module Option
  class SuggestStrategyService
    def self.call(index_symbol:, expiry_date:, params:)
      # 1) Find the instrument by index_symbol (NIFTY, BANKNIFTY, etc.)
      instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol)
      Rails.logger.debug { "Found instrument => #{instrument.inspect}" }
      raise "Invalid index symbol: #{index_symbol}" unless instrument

      # 2) Determine which expiry to use
      expiry = instrument.expiry_list.find { |e| e == expiry_date } || instrument.expiry_list.first

      # 3) Fetch real-time option chain for that expiry
      option_chain = instrument.fetch_option_chain(expiry)
      last_price = instrument.ltp || option_chain[:last_price]

      # 4) Optionally fetch short historical data (daily or intraday based on strategy)
      iv_rank = Option::ChainAnalyzer.estimate_iv_rank(option_chain)
      signal_type = resolve_signal_type(params)
      strategy_type = params[:strategy_type].presence || 'intraday'
      historical_data = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: strategy_type)

      # 5) Instantiate the new Option::ChainAnalyzer with advanced logic
      chain_analyzer = Option::ChainAnalyzer.new(
        option_chain,
        expiry: expiry,
        underlying_spot: last_price, # pass the real-time spot
        iv_rank: iv_rank,
        historical_data: historical_data # pass short daily bars
      )

      # 6) Run the analyzer to get advanced insights
      analysis = chain_analyzer.analyze(
        signal_type: signal_type,
        strategy_type: strategy_type
      )
      # => {
      #      atm_strike: 22550,
      #      best_ce_strike: {...},
      #      best_pe_strike: {...},
      #      trend: "neutral" / "bullish" / "bearish",
      #      volatility: { average_iv: 22.5, high_volatility: true },
      #      greeks_summary: {...}
      #    }

      # 7) Instantiate the StrategySuggester with the chain data + user params
      suggester = StrategySuggester.new(option_chain, last_price, params)

      # 8) Suggester uses “analysis” (plus any user’s input like :outlook, :risk, etc.)
      #    to produce an array of strategies. We return the final suggestions.
      suggester.suggest(analysis: analysis)
    end

    def self.resolve_signal_type(params)
      raw = params[:signal_type].presence || params[:instrument_type].presence
      return :ce unless raw

      normalized = raw.to_s.downcase
      return :pe if normalized.include?('pe') || normalized.include?('put')

      :ce
    end
  end
end
