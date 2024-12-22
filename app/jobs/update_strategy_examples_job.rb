class UpdateStrategyExamplesJob < ApplicationJob
  queue_as :default

  def perform(option_chain, params)
    Option::StrategyExampleUpdater.update_examples(option_chain, params)
  end
end
