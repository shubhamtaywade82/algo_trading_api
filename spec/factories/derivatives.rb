FactoryBot.define do
  factory :derivative do
    instrument
    strike_price { 2500.0 }
    option_type { "CE" }
    expiry_date { Date.today + 7.days }
    expiry_flag { "weekly" }
  end
end
