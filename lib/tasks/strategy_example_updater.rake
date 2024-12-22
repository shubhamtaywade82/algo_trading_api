namespace :strategy do
  desc "Update strategy examples with current option chain data"
  task update_examples: :environment do
    option_chain = {} # Fetch or mock the option chain data
    params = { index_symbol: "Nifty" }

    Option::StrategyExampleUpdater.update_examples(option_chain, params)
    puts "Strategy examples updated successfully."
  end
end
