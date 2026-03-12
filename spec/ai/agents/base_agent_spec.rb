# frozen_string_literal: true

require 'rails_helper'

# The ai-agents gem provides Agents::Agent and Agents::Tool.
# These specs verify our factory modules produce correctly configured agent instances
# and that our tool classes use the gem's DSL properly.

RSpec.describe 'AI Agent factories (ai-agents gem integration)' do
  describe AI::Agents::MarketStructureAgent do
    it 'builds an Agents::Agent instance' do
      agent = described_class.build
      expect(agent).to be_a(Agents::Agent)
    end

    it 'has the expected name' do
      agent = described_class.build
      expect(agent.name).to eq('Market Structure Analyst')
    end

    it 'registers DhanCandleTool and MarketSentimentTool' do
      agent      = described_class.build
      tool_names = agent.tools.map { |t| t.class.name }

      expect(tool_names).to include('AI::Tools::DhanCandleTool')
      expect(tool_names).to include('AI::Tools::MarketSentimentTool')
    end
  end

  describe AI::Agents::OptionsFlowAgent do
    it 'builds an Agents::Agent instance' do
      expect(described_class.build).to be_a(Agents::Agent)
    end

    it 'registers OptionChainTool and MarketSentimentTool' do
      agent      = described_class.build
      tool_names = agent.tools.map { |t| t.class.name }

      expect(tool_names).to include('AI::Tools::OptionChainTool')
      expect(tool_names).to include('AI::Tools::MarketSentimentTool')
    end
  end

  describe AI::Agents::TradePlannerAgent do
    it 'builds an Agents::Agent with trade-planning tools' do
      agent      = described_class.build
      tool_names = agent.tools.map { |t| t.class.name }

      expect(tool_names).to include('AI::Tools::OptionChainTool')
      expect(tool_names).to include('AI::Tools::FundsTool')
      expect(tool_names).to include('AI::Tools::DhanCandleTool')
    end
  end

  describe AI::Agents::RiskAgent do
    it 'builds an Agents::Agent with risk tools' do
      agent      = described_class.build
      tool_names = agent.tools.map { |t| t.class.name }

      expect(tool_names).to include('AI::Tools::FundsTool')
      expect(tool_names).to include('AI::Tools::PositionsTool')
    end
  end

  describe AI::Agents::OperatorAgent do
    it 'builds an Agents::Agent with all operator tools' do
      agent      = described_class.build
      tool_names = agent.tools.map { |t| t.class.name }

      expect(tool_names).to include('AI::Tools::TradeLogTool')
      expect(tool_names).to include('AI::Tools::PositionsTool')
    end
  end

  describe AI::Agents::SupervisorAgent do
    it 'builds an Agents::Agent with no direct tools (routes via handoffs)' do
      agent = described_class.build
      expect(agent.name).to eq('Trading Supervisor')
      expect(agent.tools).to be_blank
    end
  end
end
