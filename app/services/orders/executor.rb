# frozen_string_literal: true

module Orders
  class Executor < ApplicationService
    def initialize(position, reason, analysis = nil)
      @pos      = position.with_indifferent_access
      @reason   = reason
      @analysis = analysis
    end

    def call
      payload = {
        securityId: @pos['securityId'],
        transactionType: (@pos['netQty']).positive? ? 'SELL' : 'BUY',
        orderType: 'LIMIT',
        price: @pos['ltp'],
        quantity: @pos['netQty'].abs,
        exchangeSegment: @pos['exchangeSegment'],
        productType: @pos['productType'],
        validity: 'DAY'
      }

      response = Dhanhq::API::Orders.place(payload)

      if response.success?
        charges = @analysis ? Charges::Calculator.call(@pos, @analysis) : 0.0
        pnl     = @analysis ? @analysis[:pnl] : nil
        net_pnl = pnl ? (pnl - charges) : nil

        # Log to orders table
        Order.create!(
          dhan_order_id: response['orderId'],
          transaction_type: payload[:transactionType],
          product_type: payload[:productType],
          order_type: payload[:orderType],
          validity: payload[:validity],
          exchange_segment: payload[:exchangeSegment],
          security_id: payload[:securityId],
          quantity: payload[:quantity],
          price: payload[:price],
          ltp: @pos['ltp'],
          exit_reason: @reason,
          pnl: pnl,
          charges: charges,
          net_pnl: net_pnl
        )

        # Log to exit_logs table
        ExitLog.create!(
          trading_symbol: @pos['tradingSymbol'],
          security_id: @pos['securityId'],
          reason: @reason,
          order_id: response['orderId'],
          exit_price: @pos['ltp'],
          exit_time: Time.zone.now
        )

        TelegramNotifier.send_message("✅ Exit Placed: #{@pos['tradingSymbol']} | Reason: #{@reason} | Qty: #{@pos['netQty'].abs} | Price: ₹#{@pos['ltp']}")
        Rails.logger.info("[Orders::Executor] Exit placed and logged for #{@pos['tradingSymbol']} — #{@reason}")
      else
        Rails.logger.error("[Orders::Executor] Failed for #{@pos['tradingSymbol']}: #{response['message']}")
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Executor] Error for #{@pos['tradingSymbol']}: #{e.message}")
    end
  end
end
