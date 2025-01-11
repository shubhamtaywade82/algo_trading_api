# frozen_string_literal: true

module Option
  class StrategyExampleUpdater
    def self.update_examples(option_chain, params)
      Strategy.find_each do |strategy|
        suggester = StrategySuggester.new(option_chain, params)
        example = suggester.generate_example(strategy.name)
        strategy.update(example: example) if example.is_a?(String)
      end
    end
  end
end
