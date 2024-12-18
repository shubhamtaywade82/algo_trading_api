module MarketFeed
  class AdjustmentStrategy
    def initialize(data)
      @data = data
    end

    def adjust
      # Example: Place limit orders or adjust stop-losses
      Rails.logger.info "Adjusting strategy for #{@data['SecurityId']}"
    end
  end
end
