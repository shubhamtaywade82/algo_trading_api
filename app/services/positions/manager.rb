# frozen_string_literal: true

module Positions
  # Orchestrates exit logic for all current active positions.
  #
  # - Uses Positions::ActiveCache if available.
  # - Falls back to DhanHQ API if cache is empty.
  # - Skips execution during EOD hours.
  class Manager < ApplicationService
    EOD_HOUR = 15
    EOD_MIN  = 15

    # Main entry point to trigger exit logic
    #
    # @return [void]
    def call
      Positions::ActiveCache.refresh!
      return log_and_skip('Market closing — skipping exits.') if force_eod_exit?

      cache = Positions::ActiveCache.all
      if cache.blank?
        Rails.logger.warn('[Positions::Manager] Cache empty — fetching live positions from DhanHQ API')
        position_list = Dhanhq::API::Portfolio.positions
        return log_and_skip('No active positions found via DhanHQ API') if position_list.blank?

        position_list.each do |position|
          next unless valid_position?(position)

          position['ltp'] = estimate_ltp(position)
          analysis = Orders::Analyzer.call(position)
          Orders::Manager.call(position, analysis)
        end
      else
        cache.each_value do |position|
          next unless valid_position?(position)

          position['ltp'] = estimate_ltp(position)
          analysis = Orders::Analyzer.call(position)
          Orders::Manager.call(position, analysis)
        end
      end
    rescue StandardError => e
      Rails.logger.error("[Positions::Manager] Error: #{e.class} - #{e.message}")
    end

    private

    # Whether the market is near close (avoid managing exits)
    #
    # @return [Boolean]
    def force_eod_exit?
      Time.current.hour > EOD_HOUR || (Time.current.hour == EOD_HOUR && Time.current.min >= EOD_MIN)
    end

    # Whether the position is valid for evaluation
    #
    # @param pos [Hash] position data
    # @return [Boolean]
    def valid_position?(pos)
      pos['netQty'].to_i != 0 && pos['buyAvg'].to_f.positive? && pos['productType'] != 'CNC'
    end

    # Estimate LTP using net qty and unrealized profit
    #
    # @param position [Hash]
    # @return [Float, nil]
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

    # Log a reason for skipping execution
    #
    # @param reason [String]
    # @return [Boolean]
    def log_and_skip(reason)
      Rails.logger.info("[Positions::Manager] Skipped — #{reason}")
      true
    end
  end
end
