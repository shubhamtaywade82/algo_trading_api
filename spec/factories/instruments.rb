FactoryBot.define do
  factory :instrument do
    security_id { Faker::Number.number(digits: 8) }
    symbol_name { Faker::Finance.ticker }
    instrument { :equity }
    exchange { :nse }
    segment { :equity }
    isin { Faker::Alphanumeric.alphanumeric(number: 12) }
    lot_size { Faker::Number.number(digits: 2) }
    tick_size { Faker::Number.decimal(l_digits: 1, r_digits: 2) }
  end
end