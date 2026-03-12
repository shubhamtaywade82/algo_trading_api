# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AI::Tools::BaseTool do
  let(:concrete_tool_class) do
    Class.new(described_class) do
      TOOL_NAME   = 'sample_tool'
      DESCRIPTION = 'A sample tool for testing'
      PARAMETERS  = {
        type: 'object',
        properties: { value: { type: 'string' } },
        required: ['value']
      }.freeze

      def perform(args)
        { result: args['value'].upcase }
      end
    end
  end

  subject(:tool) { concrete_tool_class.new }

  describe '#name' do
    it 'returns the TOOL_NAME constant' do
      expect(tool.name).to eq('sample_tool')
    end
  end

  describe '#description' do
    it 'returns the DESCRIPTION constant' do
      expect(tool.description).to eq('A sample tool for testing')
    end
  end

  describe '#to_openai_definition' do
    it 'returns a valid OpenAI function definition' do
      defn = tool.to_openai_definition
      expect(defn[:type]).to eq('function')
      expect(defn[:function][:name]).to eq('sample_tool')
      expect(defn[:function][:description]).to be_present
      expect(defn[:function][:parameters]).to be_a(Hash)
    end
  end

  describe '#perform' do
    it 'returns the expected result' do
      result = tool.perform('value' => 'hello')
      expect(result[:result]).to eq('HELLO')
    end

    context 'when called on BaseTool directly' do
      it 'raises NotImplementedError' do
        base = described_class.new
        expect { base.perform({}) }.to raise_error(NotImplementedError)
      end
    end
  end
end
