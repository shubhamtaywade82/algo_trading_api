# frozen_string_literal: true

FactoryBot.define do
  factory :derivative do
    # Unparented by default: instrument_id is optional, the option-chain path
    # matches on `underlying_symbol`, and auto-creating one Instrument per
    # contract would collide on the instrument factory's fixed security_id.
    instrument { nil }
    sequence(:security_id) { |n| (40_000 + n).to_s }
    sequence(:symbol_name) { |n| "NIFTY-#{n}-CE" }
    exchange { 'nse' }
    segment { 'derivatives' }
    instrument_code { 'options_index' }
    underlying_symbol { 'NIFTY' }
    strike_price { 2500.0 }
    option_type { 'CE' }
    expiry_date { Time.zone.today + 7.days }
    expiry_flag { 'W' }
    lot_size { 75 }
    tick_size { 0.05 }
    active { true }
    last_seen_at { Time.current }

    trait :with_underlying do
      instrument factory: %i[instrument nifty]
    end

    trait :put do
      option_type { 'PE' }
      sequence(:symbol_name) { |n| "NIFTY-#{n}-PE" }
    end

    # Futures carry no strike or CE/PE type.
    trait :future do
      instrument_code { 'futures_index' }
      option_type { nil }
      strike_price { nil }
      sequence(:symbol_name) { |n| "NIFTY-#{n}-FUT" }
    end

    trait :expired do
      expiry_date { Time.zone.today - 7.days }
      active { false }
    end
  end
end
