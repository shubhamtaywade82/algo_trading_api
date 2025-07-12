# lib/app_config.rb
module AppConfig
  class << self
    # raw fetch
    def get(key)
      Rails.cache.fetch("app_cfg:#{key}", expires_in: 5.minutes) do
        Setting.find_by(key: key.to_s)&.value
      end
    end

    # typed helpers ---------------------------------------------------
    def bool(key, default: false)
      val = get(key)
      val.nil? ? default : ActiveModel::Type::Boolean.new.cast(val)
    end

    def f(key, default: 0.0)   = get(key)&.to_f || default
    def i(key, default: 0)     = get(key)&.to_i || default
  end
end
