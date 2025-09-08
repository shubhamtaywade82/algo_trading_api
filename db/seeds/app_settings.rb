# frozen_string_literal: true

# Seed key-value configuration settings used by the application
AppSetting.find_or_create_by!(key: 'use_adaptive_st') do |s|
  s.value = Rails.env.production?.to_s
end

AppSetting.find_or_create_by!(key: 'adaptive_st_training') do |s|
  s.value = '50'
end

AppSetting.find_or_create_by!(key: 'adaptive_st_clusters') do |s|
  s.value = '3'
end

AppSetting.find_or_create_by!(key: 'adaptive_st_alpha') do |s|
  s.value = '0.1'
end

AppSetting.find_or_create_by!(key: 'supertrend_period') do |s|
  s.value = '10'
end

AppSetting.find_or_create_by!(key: 'supertrend_multiplier') do |s|
  s.value = '2.0'
end
