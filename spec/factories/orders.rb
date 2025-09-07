# frozen_string_literal: true

FactoryBot.define do
  factory :order do
    dhan_order_id { "ORD#{SecureRandom.hex(8)}" }
    transaction_type { 'buy' }
    product_type { 'intraday' }
    order_type { 'market' }
    validity { 'day' }
    order_status { 'pending' }
    security_id { '2885' }
    quantity { 100 }

    # Don't create alert by default to avoid instrument conflicts
    alert { nil }
  end
end
