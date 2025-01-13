# frozen_string_literal: true

# spec/factories/alerts.rb
FactoryBot.define do
  factory :alert do
    ticker { 'RELIANCE' }
    instrument_type { 'equity' }
    action { 'buy' }
    order_type { 'market' }
    current_position { 'long' }
    previous_position { nil }
    strategy_type { 'intraday' }
    current_price { 2500.00 }
    high { 2510.00 }
    low { 2480.00 }
    volume { 500_000 }
    time { 5.seconds.ago }
    chart_interval { '5' }
    stop_loss { 2465.00 }
    stop_price { 2510.00 }
    take_profit { 2550.00 }
    limit_price { 2485.00 }
    trailing_stop_loss { nil }
    strategy_name { 'Enhanced AlgoTrading Alerts' }
    strategy_id { 'RELIANCE_intraday' }
    exchange { 'NSE' }
    status { 'pending' } # Default status
    error_message { nil }

    instrument factory: %i[instrument]

    trait :processed do
      status { 'processed' }
    end

    trait :failed do
      status { 'failed' }
      error_message { 'An error occurred during processing' }
    end

    trait :delayed do
      time { 2.minutes.ago } # Delayed alert
    end

    trait :invalid do
      current_price { nil } # Missing required field
    end
  end
end
