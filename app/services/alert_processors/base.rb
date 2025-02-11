# frozen_string_literal: true

module AlertProcessors
  class Base < ApplicationService
    attr_reader :alert, :exchange

    def initialize(alert)
      @alert = alert
      @exchange = alert[:exchange]
    end

    def call
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    private

    def ltp
      @ltp ||= instrument.ltp
    end

    def instrument
      @instrument ||= Instrument.find_by!(
        underlying_symbol: alert[:ticker],
        segment: segment_from_alert_type(alert[:instrument_type]),
        exchange: alert[:exchange]
      )
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for #{alert[:ticker]}"
    end

    def segment_from_alert_type(instrument_type)
      case instrument_type
      when 'index' then 'index'
      when 'stock' then 'equity'
      else instrument_type
      end
    end
  end
end
