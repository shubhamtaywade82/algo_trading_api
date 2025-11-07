# frozen_string_literal: true

# Configuration module for algorithm trading settings
module AlgoConfig
  class << self
    # Fetch configuration hash with defaults
    # @return [Hash] Configuration hash with nested keys
    def fetch
      {
        data_freshness: {
          disable_option_chain_caching: AppSetting.fetch_bool('data_freshness.disable_option_chain_caching', default: false),
          option_chain_cache_duration_minutes: AppSetting.fetch_int('data_freshness.option_chain_cache_duration_minutes', default: 2)
        }
      }
    end
  end
end


