# frozen_string_literal: true

module AlertParamsHelper
  def valid_alert_params
    {
      ticker: 'RELIANCE',
      instrument_type: 'stock',
      action: 'buy',
      order_type: 'market',
      current_position: 'long',
      strategy_type: 'intraday',
      current_price: 2500.00,
      high: 2510.00,
      low: 2480.00,
      volume: 500_000,
      time: Time.zone.now,
      chart_interval: '5',
      stop_loss: 2465.00,
      take_profit: 2550.00,
      limit_price: 2485.00,
      stop_price: 2510.00,
      strategy_name: 'Enhanced AlgoTrading Alerts',
      strategy_id: 'RELIANCE_intraday',
      exchange: 'NSE'
    }
  end
end
