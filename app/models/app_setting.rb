# frozen_string_literal: true

class AppSetting < ApplicationRecord
  self.primary_key = :key
  validates :key, :value, presence: true

  # ───────────── Convenience (kv-store style) ───────────── #
  def self.[](k)  = find_by(key: k.to_s)&.value

  def self.[]=(k, v)
    find_or_initialize_by(key: k.to_s).update!(value: v)
  end

  # ----------------- Typed fetch helpers ------------------ #
  BOOLEAN = ActiveModel::Type::Boolean.new
  FLOAT   = ActiveModel::Type::Float.new
  INTEGER = ActiveModel::Type::Integer.new

  #  Returns `true/false` with ENV & default fall-back
  def self.fetch_bool(key, default: true)
    k = key.to_s
    BOOLEAN.cast(self[k] || ENV[k.upcase] || default)
  end

  #  Float helper – e.g. option_sl_pct
  def self.fetch_float(key, default:)
    k = key.to_s
    FLOAT.cast(self[k] || ENV[k.upcase] || default)
  end

  #  Integer helper – e.g. refresh seconds, lot size
  def self.fetch_int(key, default:)
    k = key.to_s
    INTEGER.cast(self[k] || ENV[k.upcase] || default)
  end
end
