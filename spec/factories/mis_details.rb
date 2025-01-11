# frozen_string_literal: true

FactoryBot.define do
  factory :mis_detail do
    instrument
    isin { 'INE002A01018' }
    mis_leverage { 5 }
    bo_leverage { 10 }
    co_leverage { 5 }
  end
end
