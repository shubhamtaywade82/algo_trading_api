# frozen_string_literal: true

module AI
  module Tools
    # Returns available trading capital and margin information.
    class FundsTool < BaseTool
      TOOL_NAME   = 'get_funds'
      DESCRIPTION = 'Fetch available trading capital, used margin, and capital band classification for position sizing decisions.'
      PARAMETERS  = {
        type: 'object',
        properties: {},
        required: []
      }.freeze

      def perform(_args)
        funds = Dhanhq::API::Funds.get_fund_limits

        balance  = funds['availabelBalance'].to_f
        used     = funds['utilizedAmount'].to_f
        total    = balance + used

        {
          available_balance:  balance.round(2),
          used_margin:        used.round(2),
          total_capital:      total.round(2),
          capital_band:       classify_capital_band(balance),
          allocation_pct:     allocation_pct(balance),
          risk_per_trade_pct: risk_per_trade_pct(balance),
          daily_max_loss_pct: daily_max_loss_pct(balance),
          max_allocation:     (balance * allocation_pct(balance) / 100.0).round(2),
          timestamp:          Time.current.strftime('%Y-%m-%dT%H:%M:%S%z')
        }
      rescue StandardError => e
        { error: e.message }
      end

      private

      def classify_capital_band(balance)
        if balance <= 75_000
          '≤75K'
        elsif balance <= 150_000
          '≤1.5L'
        elsif balance <= 300_000
          '≤3L'
        else
          '>3L'
        end
      end

      def allocation_pct(balance)
        env = ENV['ALLOC_PCT']
        return (env.to_f * 100).round(1) if env.present?

        if balance <= 75_000     then 30.0
        elsif balance <= 150_000 then 25.0
        elsif balance <= 300_000 then 20.0
        else 20.0
        end
      end

      def risk_per_trade_pct(balance)
        env = ENV['RISK_PER_TRADE_PCT']
        return (env.to_f * 100).round(1) if env.present?

        if balance <= 75_000     then 5.0
        elsif balance <= 150_000 then 3.5
        elsif balance <= 300_000 then 3.0
        else 2.5
        end
      end

      def daily_max_loss_pct(balance)
        env = ENV['DAILY_MAX_LOSS_PCT']
        return (env.to_f * 100).round(1) if env.present?

        if balance <= 75_000     then 5.0
        elsif balance <= 150_000 then 6.0
        elsif balance <= 300_000 then 6.0
        else 5.0
        end
      end
    end
  end
end
