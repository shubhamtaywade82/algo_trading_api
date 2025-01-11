# frozen_string_literal: true

module MarketFeed
  class DataProcessor
    def initialize(data)
      @data = data
    end

    def process
      # Example logic: Parse and handle the market feed
      update_strategy if significant_movement?
    end

    private

    def significant_movement?
      # Implement logic to detect significant price changes
      @data['priceChange'] > 1.0
    end

    def update_strategy
      MarketFeed::AdjustmentStrategy.new(@data).adjust
    end
  end
end
