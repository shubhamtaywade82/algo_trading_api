# frozen_string_literal: true

module Trading
  # Confirms breakout (CE) or breakdown (PE) entry timing.
  # CE requires last close strictly above previous candle's high.
  # PE requires last close strictly below previous candle's low.
  class EntryValidator < ApplicationService
    Result = Struct.new(:valid, :reason, keyword_init: true)

    MIN_CANDLES = 3

    def initialize(direction:, candles:)
      @direction = direction.to_s.upcase
      @candles = candles
    end

    def call
      return Result.new(valid: false, reason: "Insufficient candles (#{@candles.size})") if @candles.size < MIN_CANDLES

      last = @candles.last
      prev = @candles[-2]

      last_close = last[:close].to_f
      prev_high = prev[:high].to_f
      prev_low = prev[:low].to_f

      case @direction
      when 'CE'
        if last_close > prev_high
          Result.new(valid: true, reason: 'Bullish breakout confirmed')
        else
          Result.new(valid: false, reason: "No breakout: close #{last_close} <= prev high #{prev_high}")
        end
      when 'PE'
        if last_close < prev_low
          Result.new(valid: true, reason: 'Bearish breakdown confirmed')
        else
          Result.new(valid: false, reason: "No breakdown: close #{last_close} >= prev low #{prev_low}")
        end
      else
        Result.new(valid: false, reason: "Unknown direction: #{@direction}")
      end
    end
  end
end

