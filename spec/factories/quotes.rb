# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    ltp { '9.99' }
    volume { '' }
    tick_time { '2025-05-24 13:12:37' }
    metadata { '' }

    # Don't create instrument by default to avoid conflicts
    instrument { nil }
  end
end
