# frozen_string_literal: true

# PriceMath module for handling price calculations and rounding according to DhanHQ tick size requirements
# DhanHQ uses a tick size of 0.05 for most instruments
module PriceMath
  TICK = 0.05

  # Rounds a price to the nearest valid tick
  # @param x [Numeric, nil] The price to round
  # @return [Numeric, nil] The rounded price or nil if input is nil
  def self.round_tick(x)
    return nil if x.nil?

    ((x.to_f / TICK).round * TICK).round(2)
  end

  # Floors a price to the nearest valid tick below
  # @param x [Numeric, nil] The price to floor
  # @return [Numeric, nil] The floored price or nil if input is nil
  def self.floor_tick(x)
    return nil if x.nil?

    ((x.to_f / TICK).floor * TICK).round(2)
  end

  # Ceils a price to the nearest valid tick above
  # @param x [Numeric, nil] The price to ceil
  # @return [Numeric, nil] The ceiled price or nil if input is nil
  def self.ceil_tick(x)
    return nil if x.nil?

    ((x.to_f / TICK).ceil * TICK).round(2)
  end

  # Checks if a price is valid according to tick size
  # @param x [Numeric, nil] The price to validate
  # @return [Boolean] True if the price is valid, false otherwise
  def self.valid_tick?(x)
    return false if x.nil?

    # Avoid float fuzziness: work in paise
    ((x.to_f * 100).round % (TICK * 100).to_i).zero?
  end

  # Rounds a price to 2 decimal places (legacy method for backward compatibility)
  # @param x [Numeric, nil] The price to round
  # @return [Numeric, nil] The rounded price or nil if input is nil
  def self.round_legacy(x)
    return nil if x.nil?

    x.to_f.round(2)
  end
end
