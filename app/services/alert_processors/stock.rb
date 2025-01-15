# frozen_string_literal: true

module AlertProcessors
  class Stock < Base
    def call
      strategy = determine_strategy
      Rails.logger.debug strategy
      execute_strategy(strategy)
      alert.update!(status: 'processed')
    rescue StandardError => e
      alert.update!(status: 'failed', error_message: e.message)
      Rails.logger.error("Failed to process stock alert: #{e.message}")
    end

    private

    def determine_strategy
      case alert[:strategy_type]
      when 'intraday'
        Orders::Strategies::IntradayStockStrategy.new(alert)
      when 'swing'
        Orders::Strategies::SwingStockStrategy.new(alert)
      when 'long_term'
        Orders::Strategies::StockOrderStrategy.new(alert)
      else
        raise "Unsupported strategy type: #{alert[:strategy_type]}"
      end
    end

    def execute_strategy(strategy)
      strategy.execute
    end
  end
end
