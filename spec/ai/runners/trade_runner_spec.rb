# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AI::Runners::TradeRunner do
  # Build a minimal mock for Agents::RunResult
  let(:run_result) do
    instance_double('Agents::RunResult',
      output:  output_text,
      context: { current_agent: 'Trade Planner', conversation_history: [] }
    )
  end

  describe '.run' do
    let(:output_text) { 'Market is bullish. Here is the setup.' }

    before do
      runner = instance_double('Agents::AgentRunner')
      allow(Agents::Runner).to receive(:with_agents).and_return(runner)
      allow(runner).to receive(:run).and_return(run_result)

      # Stub agent building
      allow(AI::Agents::SupervisorAgent).to receive(:build).and_return(double('supervisor', register_handoffs: nil, tools: []))
      allow(AI::Agents::MarketStructureAgent).to receive(:build).and_return(double('market', register_handoffs: nil))
      allow(AI::Agents::OptionsFlowAgent).to receive(:build).and_return(double('options', register_handoffs: nil))
      allow(AI::Agents::TradePlannerAgent).to receive(:build).and_return(double('planner', register_handoffs: nil))
      allow(AI::Agents::RiskAgent).to receive(:build).and_return(double('risk', register_handoffs: nil))
    end

    it 'returns an Agents::RunResult' do
      result = described_class.run('Generate a NIFTY trade setup')
      expect(result).to eq(run_result)
    end

    it 'passes context through to the runner' do
      ctx = { current_agent: 'Trade Planner', conversation_history: [] }
      runner = instance_double('Agents::AgentRunner')
      allow(Agents::Runner).to receive(:with_agents).and_return(runner)
      expect(runner).to receive(:run).with(anything, context: ctx).and_return(run_result)

      described_class.run('Follow-up question', context: ctx)
    end
  end

  describe '.extract_proposal' do
    context 'with a PROPOSAL: JSON block in markdown fences' do
      let(:output_text) do
        <<~TEXT
          Based on my analysis, here is the trade setup:

          PROPOSAL:
          ```json
          {"symbol":"NIFTY","direction":"CE","strike":24300,"entry_price":62.5,"stop_loss":42.0,"target":110.0,"quantity":75,"confidence":0.75}
          ```
        TEXT
      end

      it 'extracts and parses the JSON proposal' do
        proposal = described_class.extract_proposal(output_text)
        expect(proposal).to be_a(Hash)
        expect(proposal['symbol']).to eq('NIFTY')
        expect(proposal['direction']).to eq('CE')
        expect(proposal['strike']).to eq(24300)
      end
    end

    context 'with a bare JSON block in fences' do
      let(:output_text) do
        '```json{"direction":"PE","entry_price":55.0,"stop_loss":37.0,"target":95.0}```'
      end

      it 'extracts the JSON block' do
        proposal = described_class.extract_proposal(output_text)
        expect(proposal).to be_a(Hash)
        expect(proposal['direction']).to eq('PE')
      end
    end

    context 'with no JSON in output' do
      let(:output_text) { 'Market conditions are not suitable for trading today.' }

      it 'returns nil' do
        expect(described_class.extract_proposal(output_text)).to be_nil
      end
    end

    context 'with blank output' do
      it 'returns nil' do
        expect(described_class.extract_proposal('')).to be_nil
        expect(described_class.extract_proposal(nil)).to be_nil
      end
    end
  end
end
