# frozen_string_literal: true

module Orders
  # Validates that a requested place_order is safe enough to attempt
  # (market-open / allowed_to_trade + liquidity + spread + optional slippage).
  #
  # This is intentionally *not* the broker gateway. It must not place orders.
  class PlaceOrderGuard < ApplicationService
    MAX_ACTIVE_POSITIONS = 3

    def self.call(payload, logger: Rails.logger, source: nil)
      new(payload, logger: logger, source: source).call
    end

    def initialize(payload, logger:, source:)
      @payload = payload.with_indifferent_access
      @logger = logger
      @source = source
    end

    def call
      validate_allowed_to_trade!
      derivative = resolve_derivative!
      option_leg = resolve_option_leg!(derivative)

      validate_liquidity!(option_leg)
      validate_spread!(option_leg)
      validate_slippage!(option_leg)
      true
    end

    private

    def validate_allowed_to_trade!
      now = Time.current
      market_open = market_open?(now)
      active_positions = Positions::ActiveCache.all_positions.count

      return if market_open && active_positions < MAX_ACTIVE_POSITIONS

      raise "Trading not allowed (market_open=#{market_open}, active_positions=#{active_positions})"
    end

    def market_open?(time)
      return false unless MarketCalendar.trading_day?(time.to_date)

      minutes = time.hour * 60 + time.min
      minutes >= 9 * 60 + 15 && minutes <= 15 * 60 + 30
    end

    def resolve_derivative!
      security_id = @payload[:security_id].to_s
      exchange_segment = @payload[:exchange_segment].to_s

      derivative = Derivative.find_by(security_id: security_id)
      raise "Unknown derivative for security_id=#{security_id}" unless derivative

      unless derivative.exchange_segment.to_s == exchange_segment
        raise "Exchange segment mismatch for security_id=#{security_id} (expected=#{exchange_segment}, actual=#{derivative.exchange_segment})"
      end

      derivative
    end

    def resolve_option_leg!(derivative)
      chain = derivative.instrument.fetch_option_chain(derivative.expiry_date)
      raise 'Option chain unavailable' if chain.blank?

      oc = chain[:oc] || chain['oc']
      raise 'Option chain missing oc payload' if oc.blank?

      oc_indifferent = oc.with_indifferent_access
      strike_target = derivative.strike_price.to_f

      strike_row = oc_indifferent.find { |k, _v| (k.to_f - strike_target).abs < 0.000_001 }&.last
      raise "Strike not found in option chain: #{strike_target}" unless strike_row

      leg_key = option_side_key(derivative.option_type)
      leg = strike_row[leg_key] || strike_row[leg_key.to_sym]
      raise "Option leg missing for #{leg_key.to_s.upcase}" if leg.blank?

      {
        last_price: read_number(leg, :last_price, 'last_price'),
        oi: read_number(leg, :oi, 'oi', :openInterest, 'openInterest', :open_interest, 'open_interest'),
        volume: read_number(leg, :volume, 'volume', :vol, 'vol'),
        top_bid_price: read_number(leg, :top_bid_price, 'top_bid_price'),
        top_ask_price: read_number(leg, :top_ask_price, 'top_ask_price')
      }
    end

    def option_side_key(option_type)
      option_type.to_s.upcase == 'CE' ? :ce : :pe
    end

    def read_number(hash, *keys)
      keys.each do |key|
        value = hash[key]
        return value.to_f if value.present?
      end
      nil
    end

    def validate_liquidity!(option_leg)
      min_oi = Integer(ENV.fetch('DERIVATIVE_RESOLVER_MIN_OI', 1_000))
      min_volume = Integer(ENV.fetch('DERIVATIVE_RESOLVER_MIN_VOLUME', 500))

      oi = option_leg[:oi]
      volume = option_leg[:volume]
      raise 'Option chain missing OI' if oi.nil?
      raise 'Option chain missing volume' if volume.nil?

      raise "Illiquid strike (low OI: #{oi})" if oi < min_oi
      raise "Illiquid strike (low volume: #{volume})" if volume < min_volume
    end

    def validate_spread!(option_leg)
      last_price = option_leg[:last_price]
      top_bid = option_leg[:top_bid_price]
      top_ask = option_leg[:top_ask_price]

      raise 'Option chain missing last_price' if last_price.nil? || last_price <= 0.0
      raise 'Option chain missing top bid/ask for spread check' if top_bid.nil? || top_ask.nil?

      spread = (top_ask - top_bid).abs
      spread_pct = spread / last_price

      max_spread_pct = ENV.fetch('EXECUTION_MAX_SPREAD_PCT', 0.05).to_f
      raise "Spread too high (#{(spread_pct * 100).round(2)}% > #{(max_spread_pct * 100).round(2)}%)" if spread_pct > max_spread_pct
    end

    def validate_slippage!(option_leg)
      order_type = @payload[:order_type].to_s.upcase
      last_price = option_leg[:last_price]
      raise 'Option chain missing last_price for slippage check' if last_price.nil? || last_price <= 0.0

      if order_type == 'MARKET'
        return if ENV['ALLOW_MARKET_ORDER'] == 'true'

        raise 'MARKET orders blocked for autonomous execution; use LIMIT with a price band'
      end

      return unless order_type == 'LIMIT'

      provided_price = @payload[:price]&.to_f
      raise 'Missing price for LIMIT order' if provided_price.nil? || provided_price <= 0.0

      max_deviation_pct = ENV.fetch('EXECUTION_MAX_PRICE_DEVIATION_PCT', 0.02).to_f
      deviation_pct = ((provided_price - last_price).abs / last_price)

      raise "Limit price deviates from LTP by #{(deviation_pct * 100).round(2)}% > #{(max_deviation_pct * 100).round(2)}%" if deviation_pct > max_deviation_pct

      unless PriceMath.valid_tick?(provided_price)
        raise "Provided price #{provided_price} is not on the valid tick size"
      end
    end
  end
end

