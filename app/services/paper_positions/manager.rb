# frozen_string_literal: true

module PaperPositions
  # Exits local (paper) positions once a minimum profit is reached.
  #
  # This is intentionally separate from Positions::Manager which manages LIVE
  # broker positions (DhanHQ).
  class Manager < ApplicationService
    PROFIT_TARGET_RUPEES = ENV.fetch('PAPER_PROFIT_TARGET_RUPEES', '1000').to_f

    def call
      Position.where(position_type: 'LONG').where('net_qty > 0').find_each do |pos|
        next unless pos.product_type.to_s == 'margin'

        derivative = Derivative.find_by(security_id: pos.security_id.to_s)
        ltp_now = derivative&.ltp.to_f
        next unless ltp_now.positive?

        qty = pos.net_qty.to_i
        pnl = (ltp_now - pos.buy_avg.to_f) * qty

        pos.update!(unrealized_profit: pnl)

        next unless pnl >= PROFIT_TARGET_RUPEES

        pos.update!(
          sell_avg: ltp_now,
          sell_qty: (pos.sell_qty.to_i + qty),
          net_qty: 0,
          position_type: 'CLOSED',
          realized_profit: pos.realized_profit.to_f + pnl,
          unrealized_profit: 0
        )

        ExitLog.create!(
          trading_symbol: pos.trading_symbol,
          security_id: pos.security_id,
          reason: "profit_target_#{PROFIT_TARGET_RUPEES.to_i}",
          order_id: nil,
          exit_price: ltp_now,
          exit_time: Time.current
        )

        notify(<<~MSG.strip, tag: 'PAPER_TP')
          ✅ PAPER EXIT (PROFIT TARGET)
          • Symbol   : #{pos.trading_symbol}
          • Qty      : #{qty}
          • Entry    : ₹#{pos.buy_avg}
          • Exit     : ₹#{ltp_now}
          • P&L      : ₹#{pnl.round(2)}
          • Target   : ₹#{PROFIT_TARGET_RUPEES}
        MSG
      end
    rescue StandardError => e
      Rails.logger.error("[PaperPositions::Manager] Error: #{e.class} - #{e.message}")
    end
  end
end

