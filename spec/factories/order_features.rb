# frozen_string_literal: true

FactoryBot.define do
  factory :order_feature do
    instrument
    bracket_flag { 'Y' }
    cover_flag { 'Y' }
    buy_sell_indicator { 'BOTH' }
  end
end
