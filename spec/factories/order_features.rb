# frozen_string_literal: true

FactoryBot.define do
  factory :order_feature do
    # The association is polymorphic (`featureable`); `instrument` is not an
    # attribute on this model.
    featureable factory: :instrument
    bracket_flag { 'Y' }
    cover_flag { 'Y' }
    buy_sell_indicator { 'A' }
    asm_gsm_flag { 'N' }
    asm_gsm_category { 'NA' }
    mtf_leverage { 3.77 }

    trait :restricted do
      asm_gsm_flag { 'Y' }
      asm_gsm_category { 'ASM_ST_I' }
    end
  end
end
