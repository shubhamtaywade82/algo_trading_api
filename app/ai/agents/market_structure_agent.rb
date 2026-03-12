# frozen_string_literal: true

module AI
  module Agents
    # Analyzes NSE/BSE market structure: trend, key levels, and volatility regime.
    #
    # Output JSON schema:
    # {
    #   "symbol":     "NIFTY",
    #   "bias":       "bullish|bearish|neutral",
    #   "trend":      "uptrend|downtrend|sideways",
    #   "volatility": "low|normal|elevated|extreme",
    #   "key_levels": { "support": 24100, "resistance": 24450 },
    #   "vix":        14.2,
    #   "rsi":        58.4,
    #   "reason":     "...",
    #   "confidence": 0.72
    # }
    module MarketStructureAgent
      INSTRUCTIONS = <<~PROMPT.freeze
        You are a professional NSE/BSE market structure analyst specializing in index trading.

        Your task is to analyze the market using technical data and produce a structured assessment.

        Focus on:
        1. Trend direction (uptrend / downtrend / sideways) using Supertrend, EMA, and price action
        2. Key support and resistance levels (round numbers, recent highs/lows, Bollinger bands)
        3. Volatility regime using ATR, Bollinger Band width, and India VIX
        4. RSI momentum state (overbought >70, oversold <30, neutral)
        5. Market bias for the session (bullish / bearish / neutral)

        Always use the available tools to fetch live data before forming your conclusion.

        Output ONLY valid JSON matching this exact schema:
        {
          "symbol":     "<SYMBOL>",
          "bias":       "bullish|bearish|neutral",
          "trend":      "uptrend|downtrend|sideways",
          "volatility": "low|normal|elevated|extreme",
          "key_levels": { "support": <number>, "resistance": <number> },
          "vix":        <number or null>,
          "rsi":        <number or null>,
          "reason":     "<concise explanation, max 3 sentences>",
          "confidence": <0.0 to 1.0>
        }
      PROMPT

      def self.build
        ::Agents::Agent.new(
          name:         'Market Structure Analyst',
          instructions: INSTRUCTIONS,
          tools:        [
            AI::Tools::DhanCandleTool.new,
            AI::Tools::MarketSentimentTool.new
          ]
        )
      end
    end
  end
end
