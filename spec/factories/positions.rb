# frozen_string_literal: true

FactoryBot.define do
  factory :position do
    position_type { 'long' }
    product_type { 'intraday' }
    exchange_segment { 'nse_eq' }
    trading_symbol { 'RELIANCE' }
    security_id { '2885' }

    # Don't create instrument by default to avoid conflicts
    instrument { nil }
  end
end
