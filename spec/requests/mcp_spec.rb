# frozen_string_literal: true

require 'rails_helper'

MCP_ACCEPT = { 'Accept' => 'application/json, text/event-stream' }.freeze
MCP_AUTH   = { 'Authorization' => 'Bearer secret-token' }.freeze

RSpec.describe 'MCP', :mcp do
  around do |example|
    previous = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    ENV['MCP_ACCESS_TOKEN'] = 'secret-token'
    example.run
  ensure
    ENV['MCP_ACCESS_TOKEN'] = previous
  end

  describe 'POST /mcp' do
    context 'when MCP_ACCESS_TOKEN is not set' do
      around do |example|
        ENV.delete('MCP_ACCESS_TOKEN')
        example.run
      ensure
        ENV['MCP_ACCESS_TOKEN'] = 'secret-token'
      end

      it 'returns 503 Service Unavailable' do
        post '/mcp', params: '{"jsonrpc":"2.0","id":1}',
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:service_unavailable)
        json = response.parsed_body
        expect(json['error']['code']).to eq(-32_503)
        expect(json['error']['message']).to eq('Service Unavailable')
        expect(json['error']['data']).to eq('MCP_ACCESS_TOKEN must be set')
      end
    end

    context 'when MCP_ACCESS_TOKEN is set' do
      it 'returns 401 without Authorization header' do
        post '/mcp', params: '{"jsonrpc":"2.0","id":1}',
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT)
        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['error']['code']).to eq(-32_001)
        expect(json['error']['message']).to eq('Unauthorized')
      end

      it 'returns 401 with wrong Bearer token' do
        post '/mcp', params: '{"jsonrpc":"2.0","id":1}',
                     headers: { 'Content-Type' => 'application/json', 'Authorization' => 'Bearer wrong' }.merge(MCP_ACCEPT)
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 200 and initialize result with protocolVersion and capabilities' do
        body = { jsonrpc: '2.0', id: 1, method: 'initialize' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['id']).to eq(1)
        expect(json['result']['protocolVersion']).to be_present
        expect(json['result']['capabilities']['tools']).to eq('listChanged' => false)
        expect(json['result']['serverInfo']['name']).to eq('algo-trading-api')
      end

      it 'returns 200 and tools/list with registered tools' do
        body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['result']['tools']).to be_an(Array)
        names = json['result']['tools'].map { |t| t['name'] }
        expect(names).to include('get_option_chain', 'get_positions', 'get_market_data', 'place_trade', 'close_trade',
                                'scan_trade_setup', 'backtest_strategy', 'explain_trade')
      end

      it 'returns 200 and Method not found for unknown method' do
        body = { jsonrpc: '2.0', id: 2, method: 'unknown/method' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['error']['code']).to eq(-32_601)
        expect(json['error']['message']).to eq('Method not found')
      end

      it 'returns 200 and result for notifications/initialized (no id)' do
        body = { jsonrpc: '2.0', method: 'notifications/initialized' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        expect(response.body).to be_blank
      end
    end

    context 'when body exceeds max size' do
      before { stub_const('McpController::MCP_MAX_BODY_SIZE', 10) }

      it 'returns 413 with JSON-RPC error' do
        post '/mcp', params: 'x' * 11,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:payload_too_large)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['error']['code']).to eq(-32_600)
        expect(json['error']['data']).to eq('Request body exceeds maximum size')
      end
    end

    context 'when body is empty' do
      it 'returns 400 with JSON-RPC parse error' do
        post '/mcp', headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json['error']['message']).to eq('Parse error')
        expect(json['error']['data']).to eq('Request body is required')
      end
    end

    context 'when body is whitespace-only' do
      it 'returns 400 with Invalid JSON' do
        post '/mcp', params: "   \n\t  ",
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']['data']).to eq('Invalid JSON')
      end
    end

    context 'when body is invalid JSON' do
      it 'returns 400 with Parse error' do
        post '/mcp', params: 'not valid json',
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json['error']['message']).to eq('Parse error')
        expect(json['error']['data']).to eq('Invalid JSON')
      end
    end

    context 'when tools/call is used' do
      it 'returns 200 with content and isError for known tool' do
        body = {
          jsonrpc: '2.0', id: 3, method: 'tools/call',
          params: { name: 'backtest_strategy', arguments: {} }
        }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['result']['content']).to be_an(Array)
        expect(json['result']['content'].first['type']).to eq('text')
        expect(json['result']['isError']).to eq(false)
      end

      it 'returns 200 with isError true for unknown tool name' do
        body = {
          jsonrpc: '2.0', id: 4, method: 'tools/call',
          params: { name: 'nonexistent_tool', arguments: {} }
        }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['result']['isError']).to eq(true)
        text = JSON.parse(json['result']['content'].first['text'])
        expect(text['error']).to include('Unknown tool')
      end
    end
  end

  describe 'GET /mcp' do
    it 'returns 405 Method Not Allowed' do
      get '/mcp', headers: MCP_ACCEPT.merge(MCP_AUTH)
      expect(response).to have_http_status(:method_not_allowed)
    end
  end
end
