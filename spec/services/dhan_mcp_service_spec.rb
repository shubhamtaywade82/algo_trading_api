# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DhanMcpService, type: :service, mcp: true do
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
      tool_names = parsed.dig('result', 'tools')&.map { |t| t['name'] } || []
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
  end
end
