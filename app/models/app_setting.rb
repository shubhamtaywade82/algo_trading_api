class AppSetting < ApplicationRecord
  self.primary_key = :key
  validates :key, :value, presence: true

  # Convenience helpers ------------
  def self.[](key) = find_by(key: key)&.value

  def self.[]=(k, v)
    find_or_initialize_by(key: k).update!(value: v)
  end

  def self.fetch_bool(key, default: true)
    ActiveModel::Type::Boolean.new.cast(self[key] || ENV[key.upcase] || default)
  end
end
