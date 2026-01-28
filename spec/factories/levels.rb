# frozen_string_literal: true

FactoryBot.define do
  factory :level do
    instrument
    high { '9.99' }
    low { '9.99' }
    open { '9.99' }
    close { '9.99' }
    demand_zone { '9.99' }
    supply_zone { '9.99' }
    timeframe { 'MyString' }
    period_start { '2025-01-18' }
    period_end { '2025-01-18' }
  end
end
