# frozen_string_literal: true

# Seed values previously hard-coded in the application

AppSetting.find_or_create_by!(key: 'market_holidays') do |s|
  s.value = ['2025-08-15', '2025-08-27'].to_json
end

AppSetting.find_or_create_by!(key: 'valid_exchanges') do |s|
  s.value = %w[NSE BSE MCX].to_json
end

AppSetting.find_or_create_by!(key: 'valid_instruments') do |s|
  s.value = %w[OPTIDX FUTIDX OPTSTK FUTSTK FUTCUR OPTCUR FUTCOM OPTFUT EQUITY INDEX].to_json
end

AppSetting.find_or_create_by!(key: 'analysis_symbols') do |s|
  s.value = %w[NIFTY BANKNIFTY SENSEX].to_json
end

AppSetting.find_or_create_by!(key: 'feed_indexes') do |s|
  s.value = [
    { security_id: '13', exchange_segment: 'IDX_I' },
    { security_id: '25', exchange_segment: 'IDX_I' }
  ].to_json
end

AppSetting.find_or_create_by!(key: 'capital_bands_index') do |s|
  s.value = [
    { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 },
    { upto: 150_000, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 },
    { upto: 300_000, alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 },
    { upto: nil,     alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
  ].to_json
end

AppSetting.find_or_create_by!(key: 'capital_bands_stock') do |s|
  s.value = [
    { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 },
    { upto: 150_000, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 },
    { upto: 300_000, alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 },
    { upto: nil,     alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
  ].to_json
end

Rails.logger.debug { 'Seeded hard-coded configuration values.' }
