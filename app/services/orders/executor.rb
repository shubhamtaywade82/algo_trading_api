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
        security_id: @pos['securityId'] || @pos[:security_id],
        transaction_type: (@pos['netQty'] || @pos[:net_qty]).to_f.positive? ? 'SELL' : 'BUY',
        order_type: order_type,
        quantity: (@pos['netQty'] || @pos[:net_qty]).to_f.abs.to_i,
        exchange_segment: @pos['exchangeSegment'] || @pos[:exchange_segment],
        product_type: @pos['productType'] || @pos[:product_type],
        validity: 'DAY'
      }
      # Only include price for LIMIT, not MARKET orders
      payload[:price] = exit_price if order_type == 'LIMIT'

      if ENV['PLACE_ORDER'] == 'true'
        order = DhanHQ::Models::Order.new(payload)
        order.save
        order_id = order.order_id || order.id
        order_status = order.order_status || order.status

        if order_id.present? && %w[PENDING TRANSIT TRADED].include?(order_status.to_s.upcase)
          charges = @analysis[:charges] || Charges::Calculator.call(@pos, @analysis)
          pnl     = @analysis[:pnl]
          net_pnl = pnl ? (pnl - charges) : nil

          extra = @analysis[:order_type] ? " (#{@analysis[:order_type].to_s.upcase})" : ''

          notify("✅ Exit Placed#{extra}: #{@pos['tradingSymbol'] || @pos[:trading_symbol]} | Reason: #{@reason} | Qty: #{(@pos['netQty'] || @pos[:net_qty]).to_f.abs} | Price: ₹#{@pos['ltp'] || @pos[:ltp]} | Net PNL: ₹#{net_pnl}")
          Rails.logger.info("[Orders::Executor] Exit placed and logged for #{@pos['tradingSymbol'] || @pos[:trading_symbol]} — #{@reason}#{extra}")
        else
          Rails.logger.error("[Orders::Executor] Failed for #{@pos['tradingSymbol'] || @pos[:trading_symbol]}: Order status #{order_status}")
        end
      else
        dry_run(payload, @pos['tradingSymbol'])
      end
    rescue DhanHQ::OrderError => e
      if e.message.include?('Market is Closed')
        Rails.logger.warn("[Orders::Executor] Market is closed – cannot place exit order: #{e.message}")
      else
        Rails.logger.error("[Orders::Executor] Order error for #{@pos['tradingSymbol'] || @pos[:trading_symbol]}: #{e.message}")
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Executor] Error for #{@pos['tradingSymbol'] || @pos[:trading_symbol]}: #{e.message}")
    end

    def dry_run(params, symbol)
      log :info, "dry-run order → #{params}"

      notify(<<~MSG.strip, tag: 'DRYRUN')
        💡 DRY-RUN (PLACE_ORDER=false)
        • Symbol: #{symbol}
        • Type: #{params[:transaction_type]}
        • Qty: #{params[:quantity]}
      MSG
    end

    def log(level, msg)
      Rails.logger.send(level, msg.to_s)
    end
  end
end
