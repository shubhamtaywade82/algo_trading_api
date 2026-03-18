# frozen_string_literal: true

require 'rails_helper'

MCP_DEBUG_ACCEPT = { 'Accept' => 'application/json, text/event-stream' }.freeze
MCP_DEBUG_AUTH   = { 'Authorization' => 'Bearer secret-token' }.freeze

RSpec.describe 'MCP Debug endpoint', :mcp do
  around do |example|
    previous = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    ENV['MCP_ACCESS_TOKEN'] = 'secret-token'
    example.run
  ensure
    ENV['MCP_ACCESS_TOKEN'] = previous
  end

  describe 'POST /mcp/debug' do
    context 'without Authorization header' do
      it 'returns 401' do
        post '/mcp/debug',
             params: '{"jsonrpc":"2.0","id":1,"method":"tools/list"}',
             headers: { 'Content-Type' => 'application/json' }.merge(MCP_DEBUG_ACCEPT)
        expect(response).to have_http_status(:unauthorized)
        json = response.parsed_body
        expect(json['error']['code']).to eq(-32_001)
      end
    end

    context 'with correct MCP_ACCESS_TOKEN' do
      it 'returns 200 for a valid initialize request' do
        body = { jsonrpc: '2.0', id: 1, method: 'initialize' }.to_json
        post '/mcp/debug',
             params: body,
             headers: { 'Content-Type' => 'application/json' }.merge(MCP_DEBUG_ACCEPT).merge(MCP_DEBUG_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['result']['protocolVersion']).to be_present
      end
    end

    context 'tools/list' do
      it 'returns all 8 debug tool names' do
        body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
        post '/mcp/debug',
             params: body,
             headers: { 'Content-Type' => 'application/json' }.merge(MCP_DEBUG_ACCEPT).merge(MCP_DEBUG_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['result']['tools']).to be_an(Array)
        names = json['result']['tools'].pluck('name')
        expect(names).to include(
          'get_option_chain', 'scan_trade_setup', 'place_trade', 'close_trade',
          'get_positions', 'get_market_data', 'backtest_strategy', 'explain_trade'
        )
        expect(names.size).to eq(8)
      end
    end

    context 'tools/call with a debug tool' do
      it 'returns 200 with content and isError false for known debug tool' do
        body = {
          jsonrpc: '2.0', id: 2, method: 'tools/call',
          params: { name: 'backtest_strategy', arguments: {} }
        }.to_json
        post '/mcp/debug',
             params: body,
             headers: { 'Content-Type' => 'application/json' }.merge(MCP_DEBUG_ACCEPT).merge(MCP_DEBUG_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['result']['content']).to be_an(Array)
        expect(json['result']['content'].first['type']).to eq('text')
        expect(json['result']['isError']).to be(false)
      end
    end
  end

  describe 'POST /mcp tools/list' do
    it 'returns empty array (no production tools yet)' do
      body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
      post '/mcp',
           params: body,
           headers: { 'Content-Type' => 'application/json' }.merge(MCP_DEBUG_ACCEPT).merge(MCP_DEBUG_AUTH)
      expect(response).to have_http_status(:ok)
      json = response.parsed_body
      expect(json['result']['tools']).to be_an(Array)
      expect(json['result']['tools']).to be_empty
    end
  end
end
