class StrategyFactory
  STRATEGY_MAP = {
    "Supertrend Strategy + Indicator" => Strategies::SupertrendStrategy,
    "VWAP Strategy" => Strategies::VWAPStrategy
  }.freeze

  def self.build(strategy_name)
    STRATEGY_MAP.fetch(strategy_name) { raise NotImplementedError, "Unknown strategy: #{strategy_name}" }.new
  end
end