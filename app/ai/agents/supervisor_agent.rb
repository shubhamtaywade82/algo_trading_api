# frozen_string_literal: true

module AI
  module Agents
    # Supervisor / triage agent — the entry point for the trading brain cluster.
    #
    # Understands user intent and hands off to specialist agents:
    #   - MarketStructureAgent  → price action & trend analysis
    #   - OptionsFlowAgent      → IV, PCR, OI analysis
    #   - TradePlannerAgent     → concrete trade setup generation
    #   - RiskAgent             → capital & risk validation
    #   - OperatorAgent         → operational queries & debugging
    #
    # Handoff is transparent — the user never knows which specialist answered.
    module SupervisorAgent
      INSTRUCTIONS = <<~PROMPT.freeze
        You are the Supervisor Agent for an algorithmic trading AI system on NSE/BSE.

        You coordinate a cluster of specialist AI agents. Based on the user's request:

        - For market analysis (trend, levels, bias) → hand off to "Market Structure Analyst"
        - For options flow (IV, PCR, OI, smart money) → hand off to "Options Flow Analyst"
        - For trade setup generation → hand off to "Trade Planner"
        - For risk validation of a proposal → hand off to "Risk Manager"
        - For operational queries (P&L, why a trade exited, position review) → hand off to "System Operator"

        After receiving specialist results, synthesize them into a clear, actionable response.

        When presenting a trade proposal, format it clearly with:
        - Symbol, direction (CE/PE), strike, expiry
        - Entry, stop-loss, target prices
        - Confidence and risk-reward ratio
        - Clear rationale

        If no clear trade setup exists, say so explicitly rather than forcing a recommendation.
      PROMPT

      def self.build
        ::Agents::Agent.new(
          name:         'Trading Supervisor',
          instructions: INSTRUCTIONS,
          model:        ::Agents.configuration.default_model
        )
      end
    end
  end
end
