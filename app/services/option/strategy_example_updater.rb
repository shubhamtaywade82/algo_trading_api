# frozen_string_literal: true

module Option
  class StrategyExampleUpdater
    def self.update_examples(option_chain, params)
      last_price = params[:last_price] || option_chain[:last_price] || option_chain['last_price']
      last_price = last_price.to_f if last_price

      Strategy.find_each do |strategy|
        suggester = StrategySuggester.new(option_chain, last_price || 0.0, params)
        example = suggester.generate_example(strategy.name)
        strategy.update(example: example) if example.is_a?(String)
      end
    end
  end
end
