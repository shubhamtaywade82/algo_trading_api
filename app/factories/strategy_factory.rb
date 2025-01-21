# frozen_string_literal: true

class StrategyFactory
  def self.for_stock(alert)
    case alert.strategy_type
    when 'intraday'
      Strategies::Stock::IntradayStrategy.new(alert)
    when 'swing'
      Strategies::Stock::SwingStrategy.new(alert)
    when 'long_term'
      Strategies::Stock::LongTermStrategy.new(alert)
    else
      raise NotImplementedError, "Unsupported stock strategy type: #{alert.strategy_type}"
    end
  end

  def self.for_index(alert)
    case alert.strategy_type
    when 'intraday'
      Strategies::Index::IntradayStrategy.new(alert)
    when 'swing'
      Strategies::Index::SwingStrategy.new(alert)
    else
      raise NotImplementedError, "Unsupported index strategy type: #{alert.strategy_type}"
    end
  end
end
