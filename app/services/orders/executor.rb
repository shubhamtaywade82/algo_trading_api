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

      pp @analysis
      if ENV['PLACE_ORDER'] == 'true'
        response = Dhanhq::API::Orders.place(payload)

        if response['orderId'].present? && %w[PENDING TRANSIT TRADED].include?(response['orderStatus'])
          charges = @analysis[:charges] || Charges::Calculator.call(@pos, @analysis)
          pnl     = @analysis[:pnl]
          net_pnl = pnl ? (pnl - charges) : nil

          extra = @analysis[:order_type] ? " (#{@analysis[:order_type].to_s.upcase})" : ''

          notify("✅ Exit Placed#{extra}: #{@pos['tradingSymbol']} | Reason: #{@reason} | Qty: #{@pos['netQty'].abs} | Price: ₹#{@pos['ltp']}")
          Rails.logger.info("[Orders::Executor] Exit placed and logged for #{@pos['tradingSymbol']} — #{@reason}#{extra}")
        else
          Rails.logger.error("[Orders::Executor] Failed for #{@pos['tradingSymbol']}: #{response['message']}")
        end
      else
        dry_run(payload, @pos['tradingSymbol'])
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Executor] Error for #{@pos['tradingSymbol']}: #{e.message}")
    end

    def dry_run(params, symbol)
      log :info, "dry-run order → #{params}"

      notify(<<~MSG.strip, tag: 'DRYRUN')
        💡 DRY-RUN (PLACE_ORDER=false)
        • Symbol: #{symbol}
        • Type: #{params[:transactionType]}
        • Qty: #{params[:quantity]}
      MSG
    end

    def log(level, msg)
      Rails.logger.send(level, msg.to_s)
    end
  end
end
