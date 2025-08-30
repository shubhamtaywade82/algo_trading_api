FactoryBot.define do
  factory :watchlist_item do
    watchlist { nil }
    instrument { nil }
    has_options { false }
    has_futures { false }
    position { 1 }
    tags { "MyString" }
    active { false }
  end
end
