# frozen_string_literal: true

FactoryBot.define do
  factory :alert do
    ticker { 'RELIANCE' }
    instrument_type { 'stock' } # Must be a valid enum value
    action { 'buy' }
    order_type { 'market' }
    current_position { 'long' }
    previous_position { nil }
    strategy_type { 'intraday' }
    current_price { 2500.00 }
    time { 5.seconds.ago }
    chart_interval { '5' }
    strategy_name { 'Enhanced AlgoTrading Alerts' }
    strategy_id { 'RELIANCE_intraday' }
    exchange { 'NSE' }
    status { 'pending' }
    error_message { nil }
    signal_type { 'long_entry' }
    metadata { {} }

    instrument

    trait :processed do
      status { 'processed' }
    end

    trait :failed do
      status { 'failed' }
      error_message { 'An error occurred during processing' }
    end

    trait :skipped do
      status { 'skipped' }
      error_message { 'Alert skipped intentionally.' }
    end

    trait :delayed do
      time { 2.minutes.ago }
    end

    trait :invalid_price do
      current_price { nil }
    end

    trait :crypto do
      instrument_type { 'crypto' }
      ticker { 'BTCUSDT' }
      exchange { 'BINANCE' }
      strategy_name { 'Crypto Breakout Strategy' }
      strategy_id { 'BTCUSDT_crypto' }
      current_price { 67_500.50 }
    end

    trait :index do
      instrument_type { 'index' }
      ticker { 'NIFTY' }
      exchange { 'NSE' }
      strategy_name { 'Index Scalper' }
      strategy_id { 'NIFTY_index' }
      current_price { 22_350.75 }
    end

    trait :futures do
      instrument_type { 'futures' }
      ticker { 'GOLDM2025!' }
      exchange { 'MCX' }
      strategy_name { 'Commodity Trend Strategy' }
      strategy_id { 'GOLDM2025!_futures' }
      current_price { 66_555.75 }
    end

    trait :pending_status do
      status { 'pending' }
    end
  end
end
