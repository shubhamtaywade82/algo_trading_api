# frozen_string_literal: true

FactoryBot.define do
  factory :instrument do
    security_id { '2885' }
    isin { 'INE002A01018' }
    instrument { 'equity' }
    instrument_type { nil }
    underlying_security_id { nil }
    underlying_symbol { 'RELIANCE' }
    symbol_name { 'RELIANCE INDUSTRIES LTD' }
    display_name { 'Reliance Industries' }
    series { 'EQ' }
    lot_size { 1 }
    tick_size { 0.5 }
    asm_gsm_flag { 'N' }
    asm_gsm_category { 'NA' }
    mtf_leverage { 3.77 }
    exchange { 'nse' }
    segment { 'equity' }

    trait :bse do
      security_id { '500325' }
      exchange { 'bse' }
      series { 'A' }
    end
  end
end
