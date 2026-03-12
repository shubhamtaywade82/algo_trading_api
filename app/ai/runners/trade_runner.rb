# frozen_string_literal: true

module AI
  module Runners
    # Full trade planning pipeline: structure → flow → planner → risk → proposal.
    #
    # The TradePlannerAgent produces a JSON proposal. RiskAgent validates it.
    # The validated proposal is extracted and available at result[:proposal].
    #
    # Usage:
    #   result = AI::Runners::TradeRunner.run("Generate a NIFTY trade setup for today")
    #   proposal = result[:proposal]
    #   Orders::Executor.place(proposal) if Strategy::Validator.valid?(proposal)
    class TradeRunner < BaseRunner
      PIPELINE = [
        AI::Agents::MarketStructureAgent,
        AI::Agents::OptionsFlowAgent,
        AI::Agents::TradePlannerAgent,
        AI::Agents::RiskAgent
      ].freeze

      SYNTHESIZER = nil  # We extract proposal directly from pipeline results

      def run
        base_result = super

        # Extract the trade proposal from TradePlannerAgent output
        planner_result = base_result.dig(:pipeline_results, 2)
        risk_result    = base_result.dig(:pipeline_results, 3)

        proposal = extract_proposal(planner_result, risk_result)

        base_result.merge(proposal: proposal)
      end

      private

      def extract_proposal(planner_result, risk_result)
        return nil unless planner_result

        trade = planner_result[:parsed]
        risk  = risk_result&.dig(:parsed)

        return nil unless trade.is_a?(Hash)
        return nil if trade['direction'] == 'none'

        approved = risk.nil? || risk['approved'] == true

        {
          symbol:           trade['symbol'],
          direction:        trade['direction'],
          strike:           trade['strike']&.to_i,
          expiry:           trade['expiry'],
          entry_price:      trade['entry_price']&.to_f,
          stop_loss:        risk&.dig('adjusted_stop_loss')&.to_f || trade['stop_loss']&.to_f,
          target:           trade['target']&.to_f,
          quantity:         risk&.dig('adjusted_quantity')&.to_i || trade['quantity']&.to_i,
          product:          trade['product'] || 'INTRADAY',
          confidence:       trade['confidence']&.to_f,
          risk_reward:      trade['risk_reward']&.to_f,
          rationale:        trade['rationale'],
          risk_approved:    approved,
          risk_score:       risk&.dig('risk_score'),
          risk_reasons:     risk&.dig('reasons') || [],
          generated_at:     Time.current.iso8601
        }
      end
    end
  end
end
