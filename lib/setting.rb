# frozen_string_literal: true

# Wrapper around AppSetting for backwards compatibility
# Provides Setting.put and Setting.fetch methods
module Setting
  def self.put(key, value)
    AppSetting[key] = value.to_s
  end

  def self.fetch(key, default = nil)
    AppSetting[key] || default
  end

  def self.[](key)
    AppSetting[key]
  end

  def self.[]=(key, value)
    AppSetting[key] = value
  end
end

