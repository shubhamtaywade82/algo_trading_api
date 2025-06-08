# frozen_string_literal: true

module Scanners
  module Talib
    require 'technical_analysis'

    def self.ema(series, period)
      TechnicalAnalysis::Ema.calculate(series, period: period, price_key: :close).map(&:ema)
    end

    def self.rsi(series, period)
      TechnicalAnalysis::Rsi.calculate(series, period: period, price_key: :close).map(&:rsi)
    end
  end
end
