# frozen_string_literal: true

FactoryBot.define do
  factory :exit_log do
    trading_symbol { 'MyString' }
    security_id { 'MyString' }
    reason { 'MyString' }
    order_id { 'MyString' }
    exit_price { '9.99' }
    exit_time { '2025-05-12 23:13:16' }
  end
end
