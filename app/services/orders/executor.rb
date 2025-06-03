# frozen_string_literal: true

module Orders
  class Executor < ApplicationService
    def initialize(position, reason, analysis = nil)
      @pos      = position.with_indifferent_access
      @reason   = reason
      @analysis = analysis || {}
    end

    def call
      # Accept order_type and exit_price from analysis/decision, or fall back to defaults
      order_type = (@analysis[:order_type] || 'LIMIT').to_s.upcase
      exit_price = @analysis[:exit_price] || @pos['ltp']

      payload = {
        securityId: @pos['securityId'],
        transactionType: (@pos['netQty']).positive? ? 'SELL' : 'BUY',
        orderType: order_type,
        quantity: @pos['netQty'].abs,
        exchangeSegment: @pos['exchangeSegment'],
        productType: @pos['productType'],
        validity: 'DAY'
      }
      # Only include price for LIMIT, not MARKET orders
      payload[:price] = exit_price if order_type == 'LIMIT'

      if ENV['PLACE_ORDER'] == 'true'
        response = Dhanhq::API::Orders.place(payload)
      else
        dry_run(payload)
      end

      if response['orderId'].present? && %w[PENDING TRANSIT TRADED].include?(response['orderStatus'])
        charges = @analysis[:charges] || Charges::Calculator.call(@pos, @analysis)
        pnl     = @analysis[:pnl]
        net_pnl = pnl ? (pnl - charges) : nil

        # # Log to orders table
        # Order.create!(
        #   dhan_order_id: response['orderId'],
        #   transaction_type: payload[:transactionType],
        #   product_type: payload[:productType],
        #   order_type: payload[:orderType],
        #   validity: payload[:validity],
        #   exchange_segment: payload[:exchangeSegment],
        #   security_id: payload[:securityId],
        #   quantity: payload[:quantity],
        #   price: payload[:price],
        #   ltp: @pos['ltp'],
        #   exit_reason: @reason,
        #   pnl: pnl,
        #   charges: charges,
        #   net_pnl: net_pnl
        # )

        # Log to exit_logs table
        ExitLog.create!(
          trading_symbol: @pos['tradingSymbol'],
          security_id: @pos['securityId'],
          reason: @reason,
          order_id: response['orderId'],
          exit_price: @pos['ltp'],
          exit_time: Time.zone.now
        )

        extra = @analysis[:order_type] ? " (#{@analysis[:order_type].to_s.upcase})" : ''
        notify("✅ Exit Placed#{extra}: #{@pos['tradingSymbol']} | Reason: #{@reason} | Qty: #{@pos['netQty'].abs} | Price: ₹#{@pos['ltp']}")
        Rails.logger.info("[Orders::Executor] Exit placed and logged for #{@pos['tradingSymbol']} — #{@reason}#{extra}")
      else
        Rails.logger.error("[Orders::Executor] Failed for #{@pos['tradingSymbol']}: #{response['message']}")
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Executor] Error for #{@pos['tradingSymbol']}: #{e.message}")
    end

    def dry_run(params)
      log :info, "dry-run order → #{params}"

      notify(<<~MSG.strip, tag: 'DRYRUN')
        💡 DRY-RUN (PLACE_ORDER=false) – Alert ##{alert.id}
        • Symbol: #{instrument.symbol}
        • Type: #{params[:transactionType]}
        • Qty: #{params[:quantity]}
      MSG
    end
  end
end
