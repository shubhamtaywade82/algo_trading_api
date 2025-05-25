# frozen_string_literal: true

FactoryBot.define do
  factory :quote do
    instrument { nil }
    ltp { '9.99' }
    volume { '' }
    tick_time { '2025-05-24 13:12:37' }
    metadata { '' }
  end
end
