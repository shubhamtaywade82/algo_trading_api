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
      time: Time.zone.now,
      chart_interval: '5',
      strategy_name: 'Enhanced AlgoTrading Alerts',
      strategy_id: 'RELIANCE_intraday',
      exchange: 'NSE'
    }
  end
end
