module PortfolioInsights
  class Analyzer < ApplicationService
    def initialize(dhan_holdings:)
      @holdings = dhan_holdings
    end

    def call
      prompt  = build_prompt(@holdings)
      summary = Openai::ChatRouter.ask!(prompt)
      notify(summary, tag: 'PORTFOLIO_AI')
      summary
    rescue StandardError => e
      log_error("OpenAI analysis failed: #{e.message}")
      notify("❌ OpenAI failed: #{e.message}", tag: 'PORTFOLIO_AI_ERR')
      nil
    end

    # -----------------------------------------------------------------
    private

    def build_prompt(holdings)
      lines = holdings.map do |h|
        "• #{h['tradingSymbol']}  Qty:#{h['quantity']}  Avg:₹#{h['averagePrice']}  LTP:₹#{h['ltp']}"
      end
      <<~PROMPT
        Here is the current portfolio:

        #{lines.join("\n")}

        Tasks:
        1. Identify the two best and worst performers.
        2. Give exit or averaging guidance.
        3. Rate portfolio health 0-10 with reasoning.
        Keep it under 300 words.
      PROMPT
    end
  end
end
