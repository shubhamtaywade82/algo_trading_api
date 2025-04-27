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

    def ltp
      @ltp ||= begin
        fetched = instrument.ltp
        raise 'Failed to fetch LTP from Dhan' if fetched.blank?

        fetched
      end
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

    # Fetches available balance from Dhanhq::API::Funds.
    # Raises an error if the API call fails.
    #
    # @return [Float] The current available balance in the trading account.
    def available_balance
      @available_balance ||= Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    def dhan_positions
      @dhan_positions ||= Dhanhq::API::Portfolio.positions
    end
  end
end
