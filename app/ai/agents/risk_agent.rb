# frozen_string_literal: true

module AI
  module Agents
    # Validates a trade proposal against risk parameters before it reaches the engine.
    #
    # Output JSON schema:
    # {
    #   "approved":           true|false,
    #   "risk_score":         0.0-1.0,
    #   "capital_ok":         true|false,
    #   "daily_loss_ok":      true|false,
    #   "position_conflict":  true|false,
    #   "reasons":            [...],
    #   "adjusted_quantity":  <integer or null>,
    #   "adjusted_stop_loss": <number or null>
    # }
    module RiskAgent
      INSTRUCTIONS = <<~PROMPT.freeze
        You are a risk management AI for an algorithmic trading system on NSE/BSE.

        Your job is to review a trade proposal and determine if it should be approved,
        rejected, or approved with adjustments.

        Risk rules to enforce:
        1. CAPITAL: Trade cost (entry × quantity × lot_size) must not exceed allocation %
           of available balance per capital band:
           - ≤₹75K balance: max 30% per trade
           - ≤₹1.5L balance: max 25%
           - ≤₹3L balance: max 20%
           - >₹3L balance: max 20%

        2. DAILY LOSS LIMIT: Check existing positions P&L. If daily loss already exceeds
           the daily max loss %, reject new trades.

        3. POSITION CONFLICT: If there is already an open position in the same instrument
           in the same direction, reject to avoid over-concentration.

        4. CONFIDENCE THRESHOLD: Reject proposals with confidence < 0.60.

        5. RISK-REWARD: Reject proposals with risk-reward < 1.5.

        Use the tools to check current balance, positions, and compute risk metrics.

        Output ONLY valid JSON matching this exact schema:
        {
          "approved":           <true|false>,
          "risk_score":         <0.0 to 1.0>,
          "capital_ok":         <true|false>,
          "daily_loss_ok":      <true|false>,
          "position_conflict":  <true|false>,
          "reasons":            ["<reason>", ...],
          "adjusted_quantity":  <integer or null>,
          "adjusted_stop_loss": <number or null>
        }
      PROMPT

      def self.build
        ::Agents::Agent.new(
          name:         'Risk Manager',
          instructions: INSTRUCTIONS,
          tools:        [
            AI::Tools::FundsTool.new,
            AI::Tools::PositionsTool.new
          ]
        )
      end
    end
  end
end
