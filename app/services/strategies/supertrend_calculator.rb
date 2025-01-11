# frozen_string_literal: true

module Stategies
  class SupertrendCalculator
    def initialize(data, atr_period, multiplier)
      @data = data
      @atr_period = atr_period
      @multiplier = multiplier
    end

    def calculate
      calculate_tr
      calculate_atr
      calculate_supertrend
      @data
    end

    private

    def calculate_tr
      @data.each_with_index do |row, index|
        next if index.zero?

        high_low = (row[:high] - row[:low]).abs
        high_close = (row[:high] - @data[index - 1][:close]).abs
        low_close = (row[:low] - @data[index - 1][:close]).abs
        @data[index][:tr] = [high_low, high_close, low_close].max
      end
    end

    def calculate_atr
      @data.each_with_index do |row, index|
        next if index < @atr_period

        tr_values = @data[(index - @atr_period + 1)..index].pluck(:tr)
        row[:atr] = tr_values.sum / @atr_period
      end
    end

    def calculate_supertrend
      @data.each_with_index do |row, index|
        next if index < @atr_period

        row[:upper_band] = ((row[:high] + row[:low]) / 2) + (@multiplier * row[:atr])
        row[:lower_band] = ((row[:high] + row[:low]) / 2) - (@multiplier * row[:atr])
        prev_supertrend = @data[index - 1][:supertrend] if index > @atr_period
        row[:supertrend] = if prev_supertrend.nil? || row[:close] > prev_supertrend
                             row[:lower_band]
                           else
                             row[:upper_band]
                           end
      end
    end
  end
end
