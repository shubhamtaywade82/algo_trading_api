# frozen_string_literal: true

module TradingServices
  class IndexTradingService < BaseTradingService
    def execute_trade
      raise "No #{timeframe} levels found for #{symbol_name}" unless levels

      ltp = instrument.ltp
      Rails.logger.debug { "LTP: #{ltp}, Demand Zone: #{levels.demand_zone}, Supply Zone: #{levels.supply_zone}" }

      case determine_trade_action(ltp, levels)
      when :buy
        handle_demand_zone_trade
      when :sell
        handle_supply_zone_trade
      else
        Rails.logger.debug { "#{symbol_name} is within range. No trade executed." }
      end
    end

    private

    def handle_demand_zone_trade
      Rails.logger.debug { "#{symbol_name} near demand zone. Buying CALL option." }
      execute_trade_for_option(:call, levels.demand_zone)
    end

    def handle_supply_zone_trade
      Rails.logger.debug { "#{symbol_name} near supply zone. Buying PUT option." }
      execute_trade_for_option(:put, levels.supply_zone)
    end

    def execute_trade_for_option(option_type, zone)
      expiry = instrument.expiry_list.first
      option_chain = fetch_option_chain(expiry)
      analysis_results = analyze_option_chain(option_chain)
      best_strike = select_best_strike(option_chain, option_type, zone, analysis_results)

      unless best_strike
        Rails.logger.warn("No suitable strike found for #{symbol_name}, #{option_type.upcase}, zone: #{zone}.")
        return
      end

      strike_instrument = fetch_instrument_for_strike(best_strike[:strike_price], expiry, option_type)
      place_order_for_strike(strike_instrument, best_strike)
    end

    def fetch_option_chain(expiry)
      response = Dhanhq::API::Option.chain({
                                             UnderlyingScrip: instrument.security_id,
                                             UnderlyingSeg: instrument.exchange_segment,
                                             Expiry: expiry
                                           })

      raise "Failed to fetch option chain: #{response['error']}" unless response['status'] == 'success'

      response['data']
    end

    def analyze_option_chain(option_chain)
      chain_analyzer = Option::ChainAnalyzer.new(option_chain)
      analysis_results = chain_analyzer.analyze
      Rails.logger.debug analysis_results
      analysis_results
    end

    def select_best_strike(option_chain, option_type, zone, analysis_results)
      support_resistance = analysis_results[:support_resistance]
      max_pain = analysis_results[:max_pain]
      iv_trend = analysis_results[:volatility_trends][:iv_trend]

      strikes = option_chain[:oc].filter_map do |strike, data|
        next unless data[option_type.to_s]

        {
          strike_price: strike.to_i,
          last_price: data[option_type.to_s]['last_price'].to_f,
          oi: data[option_type.to_s]['oi'].to_i,
          iv: data[option_type.to_s]['implied_volatility'].to_f,
          greeks: data[option_type.to_s]['greeks']
        }
      end

      # Filter strikes near the zone, max pain, or support/resistance
      filtered_strikes = strikes.select do |strike|
        (strike[:strike_price] - zone).abs <= 100 || # Near the trade zone
          (strike[:strike_price] - max_pain).abs <= 100 || # Near max pain
          (strike[:strike_price] - support_resistance[:support]).abs <= 100 || # Near support
          (strike[:strike_price] - support_resistance[:resistance]).abs <= 100 # Near resistance
      end

      # Scoring logic with zone weighting
      filtered_strikes.max_by do |strike|
        score = strike[:oi] * strike[:iv] * (strike.dig(:greeks, :delta).abs || 0.5)
        score *= 1.2 if (strike[:strike_price] - zone).abs <= 100 # Boost score for strikes near the zone
        score *= 1.1 if iv_trend == 'increasing' # Additional boost for increasing IV trend
        score
      end
    end

    def fetch_instrument_for_strike(strike_price, expiry, option_type)
      instrument.derivatives.find_by!(
        strike_price: strike_price,
        expiry_date: expiry,
        option_type: option_type.to_s.upcase
      )
    rescue ActiveRecord::RecordNotFound
      raise "Instrument not found for strike #{strike_price}, expiry #{expiry}, and option type #{option_type}"
    end

    def place_order_for_strike(strike_instrument, best_strike)
      available_balance = fetch_available_balance
      max_allocation = available_balance * 0.5 # Allocate 50% of available balance
      quantity = calculate_quantity(best_strike[:last_price], max_allocation, strike_instrument.lot_size)

      raise 'Insufficient balance for the trade' if quantity.zero?

      order_data = {
        transactionType: 'BUY',
        exchangeSegment: strike_instrument.exchange_segment,
        productType: 'MARGIN',
        orderType: 'MARKET',
        validity: 'DAY',
        securityId: strike_instrument.security_id,
        quantity: quantity,
        price: best_strike[:last_price],
        triggerPrice: nil
      }

      result = Orders::OrdersService.new.call(order_data)
      raise "Order placement failed: #{result.failure}" unless result.success?

      Rails.logger.debug { "Order placed successfully: #{result.success}" }
    end

    def fetch_available_balance
      Dhanhq::API::Funds.balance['availabelBalance'].to_f
    rescue StandardError
      raise 'Failed to fetch available balance'
    end

    def calculate_quantity(price, max_allocation, lot_size)
      max_quantity = (max_allocation / price).floor # Calculate maximum quantity based on balance
      adjusted_quantity = (max_quantity / lot_size) * lot_size # Adjust to nearest lot size

      [adjusted_quantity, lot_size].max # Ensure at least one lot
    end
  end
end
