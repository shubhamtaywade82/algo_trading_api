# frozen_string_literal: true

module Managers
  class Holdings < Base
    PROFIT_TARGET_RANGE = (5.0..10.0) # Target profit range for exit suggestions

    def call
      log_info("Holdings Manager started at #{Time.zone.now}")
      execute_safely do
        manage_holdings
      end
    end

    private

    # Fetch all holdings from DhanHQ API
    def holdings
      Dhanhq::API::Portfolio.holdings
    rescue StandardError => e
      log_error('❌ Error fetching holdings', e)
      []
    end

    # Process each holding to evaluate potential exits
    def manage_holdings
      holdings.each do |holding|
        evaluate_and_exit_holding(holding)
      end
    end

    # Evaluate each holding for profit-taking decisions
    def evaluate_and_exit_holding(holding)
      profit_percent = calculate_unrealized_profit_percent(holding)

      if PROFIT_TARGET_RANGE.cover?(profit_percent)
        log_info("Holding #{holding['tradingSymbol']} is up #{profit_percent}%. Considering exit.")
        place_exit_order(holding)
      else
        log_info("Holding #{holding['tradingSymbol']} is not yet in profit-taking range: #{profit_percent}%.")
      end
    end

    # Calculate unrealized profit percentage for a holding
    def calculate_unrealized_profit_percent(holding)
      avg_cost_price = holding['avgCostPrice'].to_f
      current_price = fetch_ltp(holding['securityId'])
      return 0.0 if avg_cost_price.zero? || current_price.nil?

      (((current_price - avg_cost_price) / avg_cost_price) * 100).round(2)
    end

    # Fetch Last Traded Price (LTP) for a holding
    def fetch_ltp(security_id)
      response = Dhanhq::API::MarketFeed.ltp({ 'securityId' => security_id })
      return nil unless response['status'] == 'success'

      response.dig('data', security_id.to_s, 'last_price').to_f
    rescue StandardError => e
      log_error("❌ Failed to fetch LTP for security ID #{security_id}", e)
      nil
    end

    # Place an exit order if profit target is met
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
        log_info("🚀 Exit order placed for #{holding['tradingSymbol']}: Order ID #{response['orderId']}")
      else
        log_info("🔍 PLACE_ORDER is disabled. Exit order not placed for #{holding['tradingSymbol']}.")
      end
    rescue StandardError => e
      log_error("❌ Failed to place exit order for #{holding['tradingSymbol']}", e)
    end

    # Calculate the target exit price for holdings
    def calculate_exit_price(holding)
      avg_cost_price = holding['avgCostPrice'].to_f
      (avg_cost_price * 1.05).round(2) # 5% target profit
    end
  end
end
