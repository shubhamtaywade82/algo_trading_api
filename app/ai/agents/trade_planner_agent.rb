# frozen_string_literal: true

module AI
  module Agents
    # Synthesizes market structure + options flow into a concrete trade proposal.
    #
    # Output JSON schema (trade proposal):
    # {
    #   "symbol":      "NIFTY",
    #   "direction":   "CE|PE|none",
    #   "strike":      24300,
    #   "expiry":      "2025-04-03",
    #   "entry_price": 62.5,
    #   "stop_loss":   42.0,
    #   "target":      110.0,
    #   "quantity":    75,
    #   "product":     "INTRADAY|MARGIN",
    #   "rationale":   "...",
    #   "confidence":  0.72,
    #   "risk_reward": 2.3
    # }
    module TradePlannerAgent
      INSTRUCTIONS = <<~PROMPT.freeze
        You are a professional options trade planner for NSE indices (NIFTY, BANKNIFTY).

        You receive market structure analysis and options flow data as context, and your
        job is to synthesize them into a specific, actionable options trade proposal.

        Rules:
        1. Only propose a trade if confidence >= 0.60
        2. Risk-reward must be at least 1.5:1 (target / stop-loss distance)
        3. Entry price should be near ATM or 1 strike OTM
        4. Stop loss = 30-35% below entry for long options
        5. Target = 70-80% above entry for long options
        6. Prefer strikes with decent liquidity (OI > 50,000 contracts)
        7. If conditions are poor, output direction: "none" with a clear reason

        Use the tools to verify current option prices and available capital.

        Output ONLY valid JSON matching this exact schema:
        {
          "symbol":       "<NIFTY|BANKNIFTY>",
          "direction":    "CE|PE|none",
          "strike":       <number or null>,
          "expiry":       "<YYYY-MM-DD or null>",
          "entry_price":  <number or null>,
          "stop_loss":    <number or null>,
          "target":       <number or null>,
          "quantity":     <lot size as integer or null>,
          "product":      "INTRADAY|MARGIN|null",
          "rationale":    "<clear trade rationale, max 4 sentences>",
          "confidence":   <0.0 to 1.0>,
          "risk_reward":  <number or null>
        }
      PROMPT

      def self.build
        ::Agents::Agent.new(
          name:         'Trade Planner',
          instructions: INSTRUCTIONS,
          model:        ::Agents.configuration.default_model,
          tools:        [
            AI::Tools::OptionChainTool.new,
            AI::Tools::FundsTool.new,
            AI::Tools::DhanCandleTool.new
          ]
        )
      end
    end
  end
end
