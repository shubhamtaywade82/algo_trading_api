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
  end
end
