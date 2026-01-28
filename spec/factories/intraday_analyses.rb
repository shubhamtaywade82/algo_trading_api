FactoryBot.define do
  factory :intraday_analysis do
    symbol { 'MyString' }
    timeframe { 'MyString' }
    atr { '9.99' }
    atr_pct { '9.99' }
    last_close { '9.99' }
    calculated_at { '2025-07-26 12:52:21' }
  end
end
