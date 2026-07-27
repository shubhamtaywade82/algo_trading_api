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

    # Buying power to size against.
    #
    # In paper mode this is the simulated book's free capital, not the real
    # account's. Sizing off the live balance while filling into the paper book
    # is the worst of both: a funded account sizes trades the simulation never
    # constrains, and an unfunded one sizes everything to zero.
    #
    # @return [Float]
    def available_balance
      return paper_available_balance if Paper::Broker.enabled?

      @available_balance ||= begin
        funds = DhanHQ::Models::Funds.fetch
        funds.available_balance.to_f
      end
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    # Today's positions on whichever book this run trades.
    #
    # Every guard downstream — entry dedupe, flip, exit, the daily-loss check —
    # reads this. Pointed at the live book during a paper run it reports an
    # empty account, so repeated signals stack duplicate paper positions and no
    # exit ever finds anything to close.
    #
    # @return [Array<Hash>]
    def dhan_positions
      @dhan_positions ||=
        if Paper::Broker.enabled?
          Paper::Positions.dhan_shaped
        else
          DhanHQ::Models::Position.all.map(&:attributes)
        end
    end

    # Delivery holdings on whichever book this run trades.
    #
    # A CNC buy shows in the *position* book only on the day it trades; from
    # T+1 the broker reports it as a holding and the position book shows
    # nothing. Swing and long-term exits keyed to positions alone therefore
    # stopped finding the position they were meant to close, on every day but
    # the first.
    #
    # @return [Array<Hash>]
    def dhan_holdings
      @dhan_holdings ||=
        if Paper::Broker.enabled?
          Paper::Positions.dhan_holdings
        else
          DhanHQ::Models::Holding.all.map(&:attributes)
        end
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] holdings fetch failed: #{e.message}")
      []
    end

    private

    # Free margin, not gross cash: capital already committed to open paper
    # positions is not available to size the next one.
    def paper_available_balance
      @paper_available_balance ||= PaperAccount.current.free_margin.to_f
    end

    # Which book this run trades, for cache keys that must not be shared
    # between a simulated and a live session.
    def book_key
      Paper::Broker.enabled? ? 'paper' : 'live'
    end
  end
end
