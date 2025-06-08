FactoryBot.define do
  factory :swing_pick do
    instrument
    setup_type { 'breakout' }
    trigger_price { 100.0 }
    close_price { 95.0 }
    ema { 90.0 }
    rsi { 55.0 }
    volume { 100_000 }
    analysis { 'Sample explanation' }
    status { 'pending' }
  end
end
