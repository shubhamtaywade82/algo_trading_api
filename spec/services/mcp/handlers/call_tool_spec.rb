# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Mcp::Handlers::CallTool do
  describe '.call' do
    let(:tool_class) do
      Class.new do
        class << self
          attr_reader :received_args

          def name
            'test_tool'
          end

          def execute(args)
            @received_args = args
            { ok: true }
          end
        end
      end
    end

    let(:registry) do
      Class.new do
        define_singleton_method(:tools) { [tool_class] }
      end
    end

    it 'deep-symbolizes tool arguments before execution' do
      request = {
        'jsonrpc' => '2.0',
        'id' => 1,
        'params' => {
          'name' => 'test_tool',
          'arguments' => {
            'symbol' => 'NIFTY',
            'filters' => { 'interval' => '5' }
          }
        }
      }

      response = described_class.call(request, registry: registry)

      expect(response.dig(:result, :isError)).to be(false)
      expect(tool_class.received_args).to eq(symbol: 'NIFTY', filters: { interval: '5' })
    end

    it 'unwraps params-wrapped arguments and drops server_context metadata' do
      request = {
        'jsonrpc' => '2.0',
        'id' => 2,
        'params' => {
          'name' => 'test_tool',
          'arguments' => {
            'params' => {
              'symbol' => 'NIFTY',
              'server_context' => { 'request_id' => 'abc123' }
            },
            'server_context' => { 'transport' => 'openai_actions' }
          }
        }
      }

      response = described_class.call(request, registry: registry)

      expect(response.dig(:result, :isError)).to be(false)
      expect(tool_class.received_args).to eq(symbol: 'NIFTY')
    end

    it 'accepts direct tool arguments when arguments is omitted' do
      request = {
        'jsonrpc' => '2.0',
        'id' => 3,
        'params' => {
          'name' => 'test_tool',
          'symbol' => 'NIFTY',
          'server_context' => { 'transport' => 'openai_actions' }
        }
      }

      response = described_class.call(request, registry: registry)

      expect(response.dig(:result, :isError)).to be(false)
      expect(tool_class.received_args).to eq(symbol: 'NIFTY')
    end

    it 'accepts top-level arguments envelopes used by some OpenAPI action clients' do
      request = {
        'jsonrpc' => '2.0',
        'id' => 5,
        'method' => 'tools/call',
        'arguments' => {
          'name' => 'test_tool',
          'arguments' => {
            'symbol' => 'NIFTY'
          }
        }
      }

      response = described_class.call(request, registry: registry)

      expect(response.dig(:result, :isError)).to be(false)
      expect(tool_class.received_args).to eq(symbol: 'NIFTY')
    end

    it 'returns an MCP error payload for non-hash arguments' do
      request = {
        'jsonrpc' => '2.0',
        'id' => 4,
        'params' => {
          'name' => 'test_tool',
          'arguments' => 'invalid'
        }
      }

      response = described_class.call(request, registry: registry)

      expect(response.dig(:result, :isError)).to be(true)
      expect(response.dig(:result, :structuredContent, :error)).to eq('Expected Hash')
    end
  end
end
