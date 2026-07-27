# frozen_string_literal: true

require 'rails_helper'

# The Llm tools are wrappers, not reimplementations: the agent tools already
# hold this app's DhanHQ plumbing, and a second copy would drift from it.
RSpec.describe Llm::Tools::Base do
  describe 'delegation' do
    it 'passes arguments through to the agent tool' do
      agent_tool = instance_double(AI::Tools::OptionChainTool, perform: { symbol: 'NIFTY' })
      allow(AI::Tools::OptionChainTool).to receive(:new).and_return(agent_tool)

      result = Llm::Tools::OptionChain.new.execute(symbol: 'NIFTY', signal_type: 'ce')

      expect(result).to eq({ symbol: 'NIFTY' })
      expect(agent_tool).to have_received(:perform).with(nil, symbol: 'NIFTY', signal_type: 'ce')
    end

    it 'accepts the string keys a model sends' do
      agent_tool = instance_double(AI::Tools::PositionsTool, perform: [])
      allow(AI::Tools::PositionsTool).to receive(:new).and_return(agent_tool)

      Llm::Tools::Positions.new.execute('filter' => 'open')

      expect(agent_tool).to have_received(:perform).with(nil, filter: 'open')
    end

    # A raised exception aborts the whole turn; a returned error is something
    # the model can report or work around.
    it 'returns a tool failure rather than raising' do
      allow(AI::Tools::FundsTool).to receive(:new).and_raise(StandardError, 'broker down')

      expect(Llm::Tools::Funds.new.execute).to eq({ error: 'broker down' })
    end
  end

  describe 'declarations' do
    it 'gives every tool a description the model can choose on' do
      Llm::TradingAgent::TOOLS.each do |tool|
        expect(tool.description).to be_present, "#{tool} has no description"
      end
    end

    it 'names tools without the class path' do
      expect(Llm::Tools::OptionChain.new.name).to eq('option_chain')
    end

    it 'wires each tool to an agent tool' do
      Llm::TradingAgent::TOOLS.each do |tool|
        expect(tool.agent_tool).to be < AI::Tools::Base if defined?(AI::Tools::Base)
        expect(tool.agent_tool).to be_present, "#{tool} declares no delegates_to"
      end
    end
  end
end
