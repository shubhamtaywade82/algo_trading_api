# frozen_string_literal: true

module Orders
  # Orchestrates order placement and management with strict execution guards.
  # This is the "Capital-Safe" layer.
  class Manager < ApplicationService
    # Entry Point for Placement (New Orders)
    def self.place_order(payload, source: nil)
      new(payload: payload, source: source).place_order
    end

    def self.manage(position, analysis)
      new(position, analysis).manage
    end

    def initialize(*args, **kwargs)
      if args.size == 2
        @position = args[0]&.with_indifferent_access
        @analysis = args[1]
      elsif args.size == 1 && args[0].is_a?(Hash) && args[0].key?(:security_id)
        @payload = args[0].with_indifferent_access
      else
        @payload = kwargs[:payload]&.with_indifferent_access
        @source = kwargs[:source]
        @position = kwargs[:position]&.with_indifferent_access
        @analysis = kwargs[:analysis]
      end

      @security_id = @payload&.fetch(:security_id, nil)&.to_s || @position&.fetch(:securityId, nil)&.to_s
    end

    # --- Entry Management (Placement) ---

    def place_order
      validate_payload!
      
      # 0. Check for existing position
      Positions::ActiveCache.refresh!
      existing = Positions::ActiveCache.fetch(@security_id, @payload[:exchange_segment])
      if existing.present? && (existing['netQty'] || existing[:net_qty]).to_i != 0
        raise "Active position exists for security_id=#{@security_id}; refusing to place another order."
      end

      # 1. Fetch live market data for guards
      market_data = fetch_market_data
      
      # 2. Apply Guards
      validate_liquidity!(market_data)
      validate_spread!(market_data)
      
      # 3. Handle Order Type & Slippage
      final_payload = adjust_payload_for_safety(market_data)
      
      # 4. Final check with existing PlaceOrderGuard (for position limits etc)
      Orders::PlaceOrderGuard.call(final_payload, source: @source)

      # 5. Execute via Gateway
      Orders::Gateway.place_order(final_payload, source: @source)
    end

    # --- Position Management (Monitoring) ---

    def manage
      decision = Orders::RiskManager.call(@position, @analysis)

      if decision[:exit]
        merged = @analysis.merge(order_type: decision[:order_type]) if decision[:order_type]
        Orders::Executor.call(@position, decision[:exit_reason], merged || @analysis)
      elsif decision[:adjust]
        Orders::Adjuster.call(@position, decision[:adjust_params])
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Manager] Error for #{@position[:tradingSymbol]}: #{e.message}")
    end

    # Compatibility for old style calls
    def call
      manage
    end

    private

    def validate_payload!
      raise 'security_id required' if @security_id.blank?
      raise 'quantity required' if @payload[:quantity].to_i <= 0
    end

    def fetch_market_data
      derivative = Derivative.find_by!(security_id: @security_id)
      chain = derivative.instrument.fetch_option_chain(derivative.expiry_date)
      raise 'Market data unavailable' if chain.blank?

      oc = chain[:oc] || chain['oc']
      strike_row = oc.with_indifferent_access[derivative.strike_price.to_f.to_s] || 
                   oc.with_indifferent_access[derivative.strike_price.to_i.to_s]
      
      raise 'Strike data unavailable' if strike_row.blank?

      leg_key = derivative.option_type.downcase
      leg = strike_row[leg_key]
      raise "Leg data unavailable for #{leg_key}" if leg.blank?

      {
        ltp: leg['last_price'].to_f,
        bid: leg['top_bid_price'].to_f,
        ask: leg['top_ask_price'].to_f,
        oi: leg['oi'].to_i,
        volume: leg['volume'].to_i
      }
    end

    def validate_liquidity!(market_data)
      min_oi = Integer(ENV.fetch('EXECUTION_MIN_OI', 500))
      raise "Low liquidity (OI: #{market_data[:oi]} < #{min_oi})" if market_data[:oi] < min_oi
    end

    def validate_spread!(market_data)
      ltp = market_data[:ltp]
      spread = (market_data[:ask] - market_data[:bid]).abs
      max_spread_pct = ENV.fetch('EXECUTION_MAX_SPREAD_PCT', 0.02).to_f

      raise "Wide spread (#{(spread/ltp*100).round(2)}%)" if spread > (ltp * max_spread_pct)
    end

    def adjust_payload_for_safety(market_data)
      ltp = market_data[:ltp]
      max_slippage = @payload[:max_slippage_percentage]&.to_f || ENV.fetch('EXECUTION_MAX_SLIPPAGE_PCT', 0.5).to_f
      
      adjusted = @payload.dup
      adjusted[:order_type] = 'LIMIT' # Force LIMIT
      
      if @payload[:price].present?
        requested_price = @payload[:price].to_f
        max_allowed_price = ltp * (1 + max_slippage / 100.0)
        
        if @payload[:transaction_type].to_s.upcase == 'BUY' && requested_price > max_allowed_price
          raise "Price too high (Slippage check: requested #{requested_price} > max #{max_allowed_price.round(2)})"
        end
        adjusted[:price] = requested_price
      else
        buffer = ltp * 0.002
        adjusted[:price] = PriceMath.round_tick(ltp + buffer)
      end

      adjusted
    end
  end
end
