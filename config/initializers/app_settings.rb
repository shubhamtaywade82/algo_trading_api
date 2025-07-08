module AppConfig
  TTL = 30 # seconds

  def self.bool(key, default:)
    Rails.cache.fetch("setting:#{key}", expires_in: TTL) do
      AppSetting.fetch_bool(key, default: default)
    end
  rescue StandardError => e
    Rails.logger.error("[AppConfig] #{e.class}: #{e.message}")
    ActiveModel::Type::Boolean.new.cast(ENV[key.upcase] || default)
  end
end