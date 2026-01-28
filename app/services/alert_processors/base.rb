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
        if fetched.blank?
          Rails.logger.error("Failed to fetch LTP from Dhan for instrument: #{instrument.id} (#{instrument.underlying_symbol}, security_id: #{instrument.security_id}, segment: #{instrument.exchange_segment})")
          raise 'Failed to fetch LTP from Dhan'
        end
        fetched
      end
    rescue StandardError => e
      Rails.logger.error("LTP fetch error in AlertProcessor: #{e.class} - #{e.message}")
      raise
    end

    def instrument
      return @instrument if defined?(@instrument) && @instrument

      root  = alert[:ticker].to_s
      root  = root.gsub(/\d+!$/, '') if alert[:instrument_type].to_s.downcase == 'futures'

      @instrument = Instrument.find_by!(
        underlying_symbol: root,
        segment: segment_from_alert_type(alert[:instrument_type]),
        exchange: alert[:exchange]
      )
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for #{root}"
    end

    def segment_from_alert_type(instrument_type)
      case instrument_type
      when 'index' then 'index'
      when 'stock' then 'equity'
      when 'futures' then 'commodity'
      else instrument_type
      end
    end

    # Fetches available balance from DhanHQ::Models::Funds.
    # Raises an error if the API call fails.
    #
    # @return [Float] The current available balance in the trading account.
    def available_balance
      @available_balance ||= begin
        funds = DhanHQ::Models::Funds.fetch
        funds.available_balance.to_f
      end
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    def dhan_positions
      @dhan_positions ||= DhanHQ::Models::Position.all.map(&:attributes)
    end
  end
end
