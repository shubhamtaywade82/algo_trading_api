# frozen_string_literal: true

module Option
  class SuggestStrategyService
    def self.call(index_symbol:, expiry_date:, params:)
      instrument = Instrument.segment_index.find_by(underlying_symbol: index_symbol)
      raise "Invalid index symbol. #{index_symbol}" unless instrument

      expiry = instrument.expiry_list.find { |e| e['Expiry'] == expiry_date } || instrument.expiry_list.first
      option_chain = instrument.fetch_option_chain(expiry)

      analysis = ChainAnalyzer.new(option_chain).analyze
      suggester = StrategySuggester.new(option_chain, params)

      suggester.suggest(analysis: analysis)
    end
  end
end
