# frozen_string_literal: true

FactoryBot.define do
  factory :instrument do
    security_id { '2885' }
    isin { 'INE002A01018' }
    instrument { 'equity' }
    instrument_type { 'ES' }
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

    trait :nifty do
      security_id { '13' }
      isin { '1' }
      instrument { 'index' }
      instrument_type { 'INDEX' }
      underlying_symbol { 'NIFTY' }
      symbol_name { 'NIFTY' }
      display_name { 'Nifty 50' }
      series { 'X' }
      lot_size { 1 }
      tick_size { 0.1 }
      asm_gsm_flag { 'N' }
      asm_gsm_category { 'NA' }
      mtf_leverage { 0.0 }
      exchange { 'nse' }
      segment { 'index' }
    end

    trait :banknifty do
      security_id { '25' }
      isin { '2' }
      instrument { 'index' }
      instrument_type { 'INDEX' }
      underlying_symbol { 'BANKNIFTY' }
      symbol_name { 'BANKNIFTY' }
      display_name { 'Nifty Bank' }
      series { 'X' }
      lot_size { 1 }
      tick_size { 0.1 }
      asm_gsm_flag { 'N' }
      asm_gsm_category { 'NA' }
      mtf_leverage { 0.0 }
      exchange { 'nse' }
      segment { 'index' }
    end

    trait :nifty_option_call do
      security_id { '35024' }
      isin { 'NA' }
      instrument { 'options_index' }
      instrument_type { 'OP' }
      underlying_symbol { 'NIFTY' }
      symbol_name { 'NIFTY-Feb2025-29200-CE' }
      display_name { 'NIFTY 27 FEB 29200 CALL' }
      series { 'NA' }
      lot_size { 75 }
      tick_size { 0.5 }
      asm_gsm_flag { 'N' }
      asm_gsm_category { 'NA' }
      mtf_leverage { 0.0 }
      exchange { 'nse' }
      segment { 'derivatives' }
    end

    trait :nifty_option_put do
      security_id { '35025' }
      isin { 'NA' }
      instrument { 'options_index' }
      instrument_type { 'OP' }
      underlying_symbol { 'NIFTY' }
      symbol_name { 'NIFTY-Feb2025-29200-PE' }
      display_name { 'NIFTY 27 FEB 29200 PUT' }
      series { 'NA' }
      lot_size { 75 }
      tick_size { 0.5 }
      asm_gsm_flag { 'N' }
      asm_gsm_category { 'NA' }
      mtf_leverage { 0.0 }
      exchange { 'nse' }
      segment { 'derivatives' }
    end
  end
end
