FactoryBot.define do
  factory :alert do
    ticker { "RELIANCE" }
    instrument_type { "stock" }
    order_type { "market" }
    current_position { "long" }
    previous_position { nil }
    current_price { 2500.00 }
    high { 2510.00 }
    low { 2480.00 }
    volume { 500_000 }
    time { Time.zone.now }
    chart_interval { "5" }
    stop_loss { 2465.00 }
    take_profit { 2550.00 }
    trailing_stop_loss { nil }
    strategy_name { "Enhanced AlgoTrading Alerts" }
    strategy_id { "RELIANCE_intraday" }
    action { "buy" }
    exchange { "NSE" }
    status { nil }
    error_message { nil }
  end
end
