# frozen_string_literal: true

module Positions
  class Manager < ApplicationService
    EOD_HOUR = 15
    EOD_MIN  = 15

    def call
      return log_and_skip('Market closing — skipping exits.') if force_eod_exit?

      positions = Dhanhq::API::Portfolio.positions
      positions.each do |position|
        next unless valid_position?(position)

        # --- Inject LTP estimation ---
        position['ltp'] = estimate_ltp(position)

        analysis = Orders::Analyzer.call(position)
        Orders::Manager.call(position, analysis)
      end
    rescue StandardError => e
      Rails.logger.error("[Positions::Manager] Error: #{e.message}")
    end

    private

    def valid_position?(pos)
      pos['netQty'].to_i != 0 && pos['buyAvg'].to_f.positive?
    end

    def force_eod_exit?
      Time.current.hour > EOD_HOUR || (Time.current.hour == EOD_HOUR && Time.current.min >= EOD_MIN)
    end

    def log_and_skip(reason)
      Rails.logger.info("[Positions::Manager] Skipped — #{reason}")
      true
    end

    def estimate_ltp(position)
      net_qty = position['netQty'].to_f
      return nil if net_qty.zero?

      if net_qty.positive?
        # Long position
        position['buyAvg'].to_f + (position['unrealizedProfit'].to_f / net_qty)
      else
        # Short position
        position['sellAvg'].to_f - (position['unrealizedProfit'].to_f / net_qty.abs)
      end
    end
  end
end
