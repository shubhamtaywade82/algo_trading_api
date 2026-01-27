# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'MCP', type: :request, mcp: true do
  describe 'POST /mcp' do
    context 'when body is empty' do
      it 'returns 400 with JSON-RPC parse error' do
        post '/mcp', headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:bad_request)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['id']).to be_nil
        expect(json['error']['code']).to eq(-32_700)
        expect(json['error']['message']).to eq('Parse error')
        expect(json['error']['data']).to eq('Request body is required')
      end
    end

    context 'when body is present' do
      let(:mcp_server) do
        instance_double(
          MCP::Server,
          handle_json: '{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"ok"}]}}'
        )
      end

      before do
        allow(Rails.application.config.x).to receive(:dhan_mcp_server).and_return(mcp_server)
      end

      it 'forwards body to MCP server and returns its response' do
        body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
        post '/mcp', params: body, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
        expect(response.body).to include('"jsonrpc":"2.0"')
        expect(mcp_server).to have_received(:handle_json).with(body)
      end
    end
  end
end
