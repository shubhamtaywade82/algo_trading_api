# frozen_string_literal: true

class LevelService < ApplicationService
  attr_reader :instrument, :timeframe, :from_date, :to_date

  def initialize(instrument_id, timeframe, from_date, to_date)
    @instrument = Instrument.find(instrument_id)
    @timeframe = timeframe
    @from_date = from_date
    @to_date = to_date
  end

  def fetch_and_store_levels
    params = {
      securityId: instrument.security_id,
      exchangeSegment: instrument.exchange_segment,
      instrument: instrument.instrument_before_type_cast,
      expiryCode: 0,
      fromDate: from_date,
      toDate: to_date
    }
    Rails.logger.debug { "Request Params: #{params}" }

    response = Dhanhq::API::Historical.daily(params)
    pp response
    Rails.logger.debug { "API Response: #{response}" }

    levels = calculate_levels(response)
    store_levels(levels)
    levels
  end

  private

  def calculate_levels(data)
    return [] if data.empty? || !data.key?('high')

    timestamps = data['timestamp'].map { |ts| Time.zone.at(ts).strftime('%Y-%m-%d') }
    data['open'].zip(data['high'], data['low'], data['close'], data['volume'],
                     timestamps).map do |open, high, low, close, volume, date|
      {
        date: date,
        high: high,
        low: low,
        open: open,
        close: close,
        demand_zone: (low - ((high - low) * 0.25)),
        supply_zone: (high + ((high - low) * 0.25)),
        volume: volume
      }
    end
  end

  def store_levels(levels)
    return if levels.empty?

    levels.each do |level|
      Level.find_or_initialize_by(
        instrument: instrument,
        timeframe: timeframe
      ).update!(
        high: level[:high],
        low: level[:low],
        open: level[:open],
        close: level[:close],
        demand_zone: level[:demand_zone],
        supply_zone: level[:supply_zone],
        volume: level[:volume],
        period_start: level[:date],
        period_end: level[:date]
      )
    end
  end
end
