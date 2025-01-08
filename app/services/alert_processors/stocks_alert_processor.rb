module AlertProcessors
  class StocksAlertProcessor < ApplicationService
    def initialize(alert)
      @alert = alert
    end

    def call
      strategy = StrategyFactory.for_stock(alert)
      strategy.execute
    rescue => e
      @alert.update(status: "failed", error_message: e.message)
      Rails.logger.error("Failed to process stock alert: #{e.message}")
    end
  end
end
