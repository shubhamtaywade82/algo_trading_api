# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanMcpService, :mcp, type: :service do
  describe '.build_server' do
    it 'returns a server that responds to handle_json' do
      server = described_class.build_server
      expect(server).to respond_to(:handle_json)
    end

    it 'returns a server that lists tools via tools/list' do
      server = described_class.build_server
      body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
      result = server.handle_json(body)
      parsed = JSON.parse(result)
      expect(parsed).to have_key('result')
      tool_names = parsed.dig('result', 'tools')&.pluck('name') || []
      expected_tools = %w[
        get_holdings get_positions get_fund_limits get_order_list get_order_by_id
        get_order_by_correlation_id get_trade_book get_trade_history get_instrument
        get_historical_daily_data get_intraday_minute_data get_market_ohlc
        get_option_chain get_expiry_list get_edis_inquiry
      ]
      expected_tools.each do |name|
        expect(tool_names).to include(name), "expected tool #{name} to be listed"
      end
    end

    it 'handles params-wrapped arguments for a market tool call' do
      server = described_class.build_server
      body = {
        jsonrpc: '2.0',
        id: 2,
        method: 'tools/call',
        params: {
          name: 'get_market_ohlc',
          arguments: {
            exchange_segment: 'IDX_I',
            symbol: 'NIFTY'
          }
        }
      }.to_json

      result = server.handle_json(body)
      parsed = JSON.parse(result)
      text = parsed.dig('result', 'content', 0, 'text').to_s

      expect(parsed['jsonrpc']).to eq('2.0')
      expect(text).not_to include('UnrecognizedKwargsError')
      expect(text).not_to include('unknown keyword: :params')
      expect(text).not_to include('Unexpected argument(s): server_context')
    end

    it 'handles params-wrapped calls for no-argument tools without kwargs errors' do
      server = described_class.build_server
      body = {
        jsonrpc: '2.0',
        id: 3,
        method: 'tools/call',
        params: {
          name: 'get_positions',
          arguments: {}
        }
      }.to_json

      result = server.handle_json(body)
      parsed = JSON.parse(result)
      text = parsed.dig('result', 'content', 0, 'text').to_s

      expect(parsed['jsonrpc']).to eq('2.0')
      expect(text).not_to include('UnrecognizedKwargsError')
      expect(text).not_to include('unknown keyword: :params')
      expect(text).not_to include('Unexpected argument(s): server_context')
    end

    it 'returns valid JSON-RPC for unknown method' do
      server = described_class.build_server
      body = { jsonrpc: '2.0', id: 99, method: 'unknown/method' }.to_json
      result = server.handle_json(body)
      parsed = JSON.parse(result)
      expect(parsed['jsonrpc']).to eq('2.0')
      expect(parsed['id']).to eq(99)
      expect(parsed.key?('error') || parsed.key?('result')).to be true
    end
  end
end
