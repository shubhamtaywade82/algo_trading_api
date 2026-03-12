# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AI::Agents::BaseAgent do
  # Minimal concrete agent for testing
  let(:echo_tool_class) do
    Class.new(AI::Tools::BaseTool) do
      TOOL_NAME   = 'echo'
      DESCRIPTION = 'Echoes the input back'
      PARAMETERS  = {
        type: 'object',
        properties: { message: { type: 'string' } },
        required: ['message']
      }.freeze

      def perform(args)
        { echoed: args['message'] }
      end
    end
  end

  let(:test_agent_class) do
    tool = echo_tool_class
    Class.new(described_class) do
      INSTRUCTIONS = 'You are a test agent. Echo back anything asked.'
      TOOLS        = [tool].freeze
    end
  end

  describe '.run' do
    context 'when the LLM returns a direct text response' do
      let(:openai_response) do
        {
          'choices' => [{
            'message' => { 'content' => 'Hello from the agent', 'tool_calls' => nil }
          }]
        }
      end

      before do
        client = instance_double(OpenAI::Client)
        allow(OpenAI::Client).to receive(:instance).and_return(client)
        allow(Openai::Client).to receive(:instance).and_return(client)
        allow(client).to receive(:chat).and_return(openai_response)
      end

      it 'returns output with the LLM text' do
        result = test_agent_class.run('Hello')
        expect(result[:output]).to eq('Hello from the agent')
        expect(result[:iterations]).to eq(1)
        expect(result[:tool_calls]).to be_empty
      end

      it 'includes the agent name in the result' do
        result = test_agent_class.run('Hello')
        expect(result[:agent]).to be_present
      end
    end

    context 'when the LLM returns a tool call followed by a text response' do
      let(:tool_call_response) do
        {
          'choices' => [{
            'message' => {
              'content' => nil,
              'tool_calls' => [{
                'id'       => 'call_abc123',
                'function' => { 'name' => 'echo', 'arguments' => '{"message":"test"}' }
              }]
            }
          }]
        }
      end

      let(:final_response) do
        {
          'choices' => [{
            'message' => { 'content' => 'Echoed: test', 'tool_calls' => nil }
          }]
        }
      end

      before do
        client = instance_double(OpenAI::Client)
        allow(OpenAI::Client).to receive(:instance).and_return(client)
        allow(Openai::Client).to receive(:instance).and_return(client)
        allow(client).to receive(:chat).and_return(tool_call_response, final_response)
      end

      it 'executes the tool and continues the loop' do
        result = test_agent_class.run('Please echo "test"')
        expect(result[:output]).to eq('Echoed: test')
        expect(result[:iterations]).to eq(2)
        expect(result[:tool_calls].length).to eq(1)
        expect(result[:tool_calls].first[:tool_name]).to eq('echo')
        expect(result[:tool_calls].first[:result]).to eq({ echoed: 'test' })
      end
    end

    context 'when LLM returns JSON in the output' do
      let(:json_response) do
        {
          'choices' => [{
            'message' => {
              'content'    => '{"bias":"bullish","confidence":0.75}',
              'tool_calls' => nil
            }
          }]
        }
      end

      before do
        client = instance_double(OpenAI::Client)
        allow(OpenAI::Client).to receive(:instance).and_return(client)
        allow(Openai::Client).to receive(:instance).and_return(client)
        allow(client).to receive(:chat).and_return(json_response)
      end

      it 'parses JSON into the :parsed key' do
        result = test_agent_class.run('Analyze NIFTY')
        expect(result[:parsed]).to eq({ 'bias' => 'bullish', 'confidence' => 0.75 })
      end
    end

    context 'when the LLM call raises an error' do
      before do
        client = instance_double(OpenAI::Client)
        allow(OpenAI::Client).to receive(:instance).and_return(client)
        allow(Openai::Client).to receive(:instance).and_return(client)
        allow(client).to receive(:chat).and_raise(StandardError, 'API timeout')
      end

      it 'returns an error result without raising' do
        result = test_agent_class.run('Hello')
        expect(result[:error]).to be true
        expect(result[:output]).to include('Agent error')
      end
    end
  end
end
