# frozen_string_literal: true

module Managers
  class Holdings < Base
    PROFIT_TARGET_RANGE = (5.0..10.0) # Target profit range for exits

    def call
      log_info('📊 Executing Holdings Manager')
      execute_safely { manage_holdings }
    end

    private

    # Fetch holdings from DhanHQ API
    def holdings
      Dhanhq::API::Portfolio.holdings
    rescue StandardError => e
      log_error('❌ Error fetching holdings', e)
      []
    end

    # Process each holding for exit evaluation
    def manage_holdings
      holdings.each { |holding| evaluate_and_exit_holding(holding) }
    end

    # Evaluate profit & decide whether to exit
    def evaluate_and_exit_holding(holding)
      profit_percent = calculate_unrealized_profit_percent(holding)

      if PROFIT_TARGET_RANGE.cover?(profit_percent)
        log_info("✅ Holding #{holding['tradingSymbol']} is up #{profit_percent}%. Placing exit order.")
        place_exit_order(holding)
      else
        log_info("📉 Holding #{holding['tradingSymbol']} is at #{profit_percent}%, not in exit range.")
      end
    end

    # Calculate profit percentage
    def calculate_unrealized_profit_percent(holding)
      avg_cost_price = holding['avgCostPrice'].to_f
      current_price = fetch_ltp_from_instrument(holding['securityId'])

      return 0.0 if avg_cost_price.zero? || current_price.nil?

      (((current_price - avg_cost_price) / avg_cost_price) * 100).round(2)
    end

    # Fetch LTP from Instrument model (Uses cache & API fallback)
    def fetch_ltp_from_instrument(security_id)
      instrument = fetch_instrument_by_security_id(security_id)
      return unless instrument

      instrument.ltp
    end

    # Find instrument by security ID
    def fetch_instrument_by_security_id(security_id)
      Instrument.find_by(security_id: security_id).tap do |instrument|
        log_error("⚠️ Instrument not found for Security ID: #{security_id}") unless instrument
      end
    end

    # Place exit order
    def place_exit_order(holding)
      order_params = {
        transactionType: 'SELL',
        exchangeSegment: 'NSE_EQ',
        productType: 'CNC',
        orderType: 'LIMIT',
        securityId: holding['securityId'],
        quantity: holding['availableQty'],
        price: calculate_exit_price(holding)
      }

      if ENV['PLACE_ORDER'] == 'true'
        response = Dhanhq::API::Orders.place(order_params)
        log_info("🚀 Exit order placed for #{holding['tradingSymbol']} (Order ID: #{response['orderId']})")
      else
        log_info("🔍 PLACE_ORDER disabled. Exit order not placed for #{holding['tradingSymbol']}.")
      end
    rescue StandardError => e
      log_error("❌ Failed to place exit order for #{holding['tradingSymbol']}", e)
    end

    # Calculate target exit price (5% profit)
    def calculate_exit_price(holding)
      (holding['avgCostPrice'].to_f * 1.05).round(2)
    end
  end
end
