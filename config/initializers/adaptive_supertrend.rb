# frozen_string_literal: true

ENV['USE_ADAPTIVE_ST'] ||= Rails.env.production? ? 'true' : 'false'
ENV['ADAPTIVE_ST_TRAINING'] ||= '50'
ENV['ADAPTIVE_ST_CLUSTERS'] ||= '3'
ENV['ADAPTIVE_ST_ALPHA'] ||= '0.1'

require Rails.root.join('app/services/indicators/supertrend_builder.rb')
