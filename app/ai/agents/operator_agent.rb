# frozen_string_literal: true

module AI
  module Agents
    # Operator/debug agent that answers natural-language questions about system state.
    #
    # Examples:
    #   OperatorAgent.run("Why did trade #214 exit early?")
    #   OperatorAgent.run("Show me all losing positions from today")
    #   OperatorAgent.run("What was our P&L yesterday?")
    #   OperatorAgent.run("How many NIFTY calls did we buy this week?")
    class OperatorAgent < BaseAgent
      INSTRUCTIONS = <<~PROMPT.freeze
        You are a trading system operator assistant for an algorithmic trading platform
        on NSE/BSE using DhanHQ. You help answer operational questions about the system.

        You have access to:
        - Current open positions
        - Trade execution logs and exit events
        - Order history
        - TradingView alert records

        When answering:
        1. Always fetch relevant data via tools first
        2. Be concise and precise — this is operational data
        3. Include specific numbers, timestamps, and reasons where available
        4. If you cannot find the answer, say so clearly rather than guessing
        5. Format monetary values in Indian Rupees (₹)
        6. Format timestamps in IST (Asia/Kolkata)

        You do NOT place trades or modify positions — you only read and explain.
      PROMPT

      TOOLS = [
        AI::Tools::PositionsTool,
        AI::Tools::TradeLogTool,
        AI::Tools::FundsTool,
        AI::Tools::DhanCandleTool
      ].freeze
    end
  end
end
