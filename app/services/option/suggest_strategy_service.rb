module Option
  class SuggestStrategyService
    def self.call(index_symbol:, expiry_date:, params:)
      instrument = Instrument.indices.find_by(underlying_symbol: index_symbol, segment: Segment.find_by(segment_code: "I"))
      raise "Invalid index symbol.#{index_symbol}" if instrument.nil?

      option_chain = instrument.fetch_option_chain(expiry_date)

      analysis = ChainAnalyzer.new(option_chain).analyze
      suggester = StrategySuggester.new(option_chain, params)

      suggester.suggest(
        analysis: analysis,
        option_preference: params[:option_preference] || "both",
        outlook: params[:outlook],
        volatility: params[:volatility],
        risk: params[:risk]
      )
    end
  end
end
