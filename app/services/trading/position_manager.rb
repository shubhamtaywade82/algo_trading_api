# frozen_string_literal: true

module Trading
  # Manages open option positions: break-even SL, trailing SL, partial exit, force exit.
  class PositionManager < ApplicationService
    Result = Struct.new(:success, :action, :message, :details, keyword_init: true)

    LOT_SIZES = { 'NIFTY' => 75, 'BANKNIFTY' => 15, 'SENSEX' => 10 }.freeze
    DEFAULT_TRAIL_PCT = 5.0

    def initialize(security_id:, exchange_segment:, action:, params: {})
      @security_id = security_id
      @exchange_segment = exchange_segment
      @action = action.to_sym
      @params = params.with_indifferent_access
    end

    def call
      position = Positions::ActiveCache.fetch(@security_id, @exchange_segment)
      return failure('Position not found') unless position

      case @action
      when :move_sl_to_be
        move_sl_to_break_even(position)
      when :trail_sl
        trail_stop_loss(position)
      when :partial_exit
        partial_exit(position)
      when :force_exit
        force_exit(position)
      else
        failure("Unknown action: #{@action}")
      end
    end

    private

    def move_sl_to_break_even(position)
      entry_price = position['costPrice'].to_f
      return failure('Entry price unavailable') if entry_price.zero?

      Orders::Adjuster.call(position, { trigger_price: entry_price })
      success_result(:move_sl_to_be, 'SL moved to break-even', { new_trigger_price: entry_price })
    rescue StandardError => e
      failure("Adjuster failed: #{e.message}")
    end

    def trail_stop_loss(position)
      trail_pct = @params[:trail_pct]&.to_f || DEFAULT_TRAIL_PCT
      analysis = Orders::Analyzer.call(position)
      ltp = analysis[:ltp].to_f
      return failure('LTP unavailable for trailing SL') if ltp.zero?

      long = analysis[:long]
      new_trigger = long ? ltp * (1 - trail_pct / 100.0) : ltp * (1 + trail_pct / 100.0)
      new_trigger = new_trigger.round(2)

      Orders::Adjuster.call(position, { trigger_price: new_trigger })
      success_result(:trail_sl, "SL trailed at #{trail_pct}% from LTP #{ltp}", { new_trigger_price: new_trigger, trail_pct: trail_pct })
    rescue StandardError => e
      failure("Trail SL failed: #{e.message}")
    end

    def partial_exit(position)
      net_qty = position['netQty'].to_i.abs
      lot_size = detect_lot_size(position)

      half_lots = [(net_qty / lot_size / 2.0).ceil, 1].max
      half_qty = half_lots * lot_size

      payload = build_exit_payload(position, half_qty)
      Orders::Gateway.place_order(payload, source: 'mcp_partial_exit')
      success_result(:partial_exit, "Partial exit: #{half_qty} qty", { qty_exited: half_qty })
    rescue StandardError => e
      failure("Partial exit failed: #{e.message}")
    end

    def force_exit(position)
      analysis = Orders::Analyzer.call(position)
      Orders::Executor.call(position, 'MCP_FORCE_EXIT', analysis.merge(order_type: 'MARKET'))
      success_result(:force_exit, 'Force exit placed', { order_type: 'MARKET' })
    rescue StandardError => e
      failure("Force exit failed: #{e.message}")
    end

    def detect_lot_size(position)
      symbol = position['tradingSymbol'].to_s
      LOT_SIZES.each { |k, v| return v if symbol.include?(k) }
      1
    end

    def build_exit_payload(position, qty)
      transaction_type = position['netQty'].to_i.positive? ? 'SELL' : 'BUY'
      {
        'dhanClientId' => position['dhanClientId'],
        'transactionType' => transaction_type,
        'exchangeSegment' => @exchange_segment,
        'productType' => position['productType'],
        'orderType' => 'MARKET',
        'validity' => 'DAY',
        'securityId' => @security_id,
        'quantity' => qty
      }
    end

    def success_result(action, message, details)
      Result.new(success: true, action: action, message: message, details: details)
    end

    def failure(message)
      Result.new(success: false, action: @action, message: message, details: {})
    end
  end
end

