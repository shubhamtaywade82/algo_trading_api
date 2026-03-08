# frozen_string_literal: true

module Market
  # Extracts loading and normalization logic from CandleSeries
  class CandleLoader < ApplicationService
    def initialize(candle_series, response)
      @candle_series = candle_series
      @response = response
    end

    def call
      normalise_candles(@response).each do |row|
        @candle_series.add_candle(
          Candle.new(
            ts: row[:timestamp],
            open: row[:open],
            high: row[:high],
            low: row[:low],
            close: row[:close],
            volume: row[:volume]
          )
        )
      end
    end

    private

    def normalise_candles(resp)
      return [] if resp.blank?
      return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

      raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp['high'].is_a?(Array)

      size = resp['high'].size
      (0...size).map do |i|
        {
          open: resp['open'][i].to_f,
          close: resp['close'][i].to_f,
          high: resp['high'][i].to_f,
          low: resp['low'][i].to_f,
          timestamp: Time.zone.at(resp['timestamp'][i]),
          volume: resp['volume'][i].to_i
        }
      end
    end

    def slice_candle(c)
      {
        open: (c[:open] || c['open']).to_f,
        high: (c[:high] || c['high']).to_f,
        low: (c[:low] || c['low']).to_f,
        close: (c[:close] || c['close']).to_f,
        timestamp: c[:timestamp] || c['timestamp'],
        volume: (c[:volume] || c['volume'] || 0).to_i
      }
    end
  end
end
