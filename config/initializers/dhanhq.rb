# frozen_string_literal: true

require 'dhan_hq'

DhanHQ.configure_with_env
DhanHQ.logger.level = (ENV['DHAN_LOG_LEVEL'] || 'INFO').upcase.then { |level| Logger.const_get(level) }

# Load backwards-compatibility layer for legacy Dhanhq::API calls
# This file is excluded from Zeitwerk autoloading because it defines Dhanhq::API
# (not Dhanhq::Api as Zeitwerk expects based on the file name)
require Rails.root.join('lib', 'dhanhq', 'api').to_s
