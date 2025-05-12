FactoryBot.define do
  factory :postback_log do
    order_id { "" }
    dhan_order_id { "MyString" }
    event { "MyString" }
    payload { "" }
  end
end
