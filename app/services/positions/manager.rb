# frozen_string_literal: true

# app/services/position_manager.rb

module Positions
  class Manager < ApplicationService
    RISK_REWARD_RATIO = 2.0
    MAX_ACCEPTABLE_LOSS_PERCENT = 50.0
    TRAILING_SL_PERCENT = 10.0
    TRAILING_TP_PERCENT = 20.0
    BROKERAGE = 20.0
    GST_RATE = 0.18
    STT_RATE = 0.025 / 100
    TRANSACTION_CHARGES_RATE = 0.003503 / 100
    SEBI_FEES_RATE = 0.0001 / 100
    STAMP_DUTY_RATE = 0.003 / 100
    IPFT_RATE = 0.00005 / 100

    def call
      positions.each do |position|
        analysis = analyze_position(position)
        charges = calculate_charges(position, analysis)
        decision = decide_exit(position, analysis, charges)

        decision[:exit] ? place_exit_order(position, decision[:quantity]) : adjust_trailing_stop(position, analysis)
      end
    rescue StandardError
      Rails.logger.error("PositionManager execution error: #{e.message}")
    end

    private

    def positions
      @positions ||= Dhanhq::API::Portfolio.positions
    end

    def analyze_position(position)
      entry_price = position['buyAvg'].to_f
      current_price = position['ltp'].to_f
      quantity = position['netQty'].abs
      pnl = (current_price - entry_price) * ((position['netQty']).positive? ? 1 : -1) * quantity

      {
        entry_price: entry_price,
        current_price: current_price,
        quantity: quantity,
        pnl: pnl,
        pnl_percent: (pnl / (entry_price * quantity).abs * 100).round(2),
        risk_reward_ratio: (pnl / entry_price.abs).round(2)
      }
    end

    # **Determine if an exit should be executed**
    def decide_exit(_position, analysis, charges)
      net_profit = analysis[:pnl] - charges
      loss_threshold = analysis[:entry_price] * MAX_ACCEPTABLE_LOSS_PERCENT / 100.0
      profit_target = analysis[:entry_price] * RISK_REWARD_RATIO

      if net_profit >= profit_target
        { exit: true, quantity: analysis[:quantity] }
      elsif analysis[:pnl] <= -loss_threshold
        { exit: true, quantity: analysis[:quantity] }
      else
        { exit: false }
      end
    end

    # ✅ **Place exit order directly**
    def place_exit_order(position, quantity)
      order_payload = {
        securityId: position['securityId'],
        quantity: quantity,
        transactionType: (position['netQty']).positive? ? 'SELL' : 'BUY',
        exchangeSegment: position['exchangeSegment'],
        productType: position['productType'],
        orderType: 'MARKET',
        validity: 'DAY'
      }

      response = Dhanhq::API::Orders.place(order_payload)
      if response.success?
        Rails.logger.info("Order placed successfully for #{position['tradingSymbol']}")
      else
        Rails.logger.error("Order placement failed for #{position['tradingSymbol']}: #{response.status} - #{response.body}")
      end
    rescue StandardError
      Rails.logger.error("Order placement error for #{position['tradingSymbol']}: #{e.message}")
    end

    # ✅ **Adjust trailing stop-loss dynamically**
    def adjust_trailing_stop(position, analysis)
      trailing_stop_price = (analysis[:current_price] * (1 - (TRAILING_SL_PERCENT / 100.0))).round(2)
      modify_payload = { triggerPrice: trailing_stop_price }

      response = Dhanhq::API::Orders.modify(position['orderId'], modify_payload)
      if response['status'] == 'success'
        Rails.logger.info("Trailing stop updated for #{position['tradingSymbol']} to #{trailing_stop_price}")
      else
        Rails.logger.error("Failed to update trailing stop for #{position['tradingSymbol']}: #{response['omsErrorDescription']}")
      end
    rescue StandardError
      Rails.logger.error("Error updating trailing stop for #{position['tradingSymbol']}: #{e.message}")
    end

    def calculate_charges(_position, analysis)
      turnover = (analysis[:entry_price] + analysis[:current_price]) * analysis[:quantity]
      brokerage = BROKERAGE
      transaction_charges = turnover * TRANSACTION_CHARGES_RATE
      sebi_fees = turnover * SEBI_FEES_RATE
      stt = turnover * STT_RATE
      stamp_duty = turnover * STAMP_DUTY_RATE
      ipft = turnover * IPFT_RATE
      gst = (brokerage + transaction_charges + sebi_fees + stt + stamp_duty + ipft) * GST_RATE

      (brokerage + transaction_charges + sebi_fees + stt + stamp_duty + ipft + gst).round(2)
    end
  end
end
