# frozen_string_literal: true

require 'rails_helper'

# Streamable HTTP (MCP) requires Accept: application/json, text/event-stream for POST
MCP_ACCEPT = { 'Accept' => 'application/json, text/event-stream' }.freeze
MCP_AUTH = { 'Authorization' => 'Bearer secret-token' }.freeze

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

      it 'forwards to MCP transport with valid Bearer token' do
        transport = instance_double(MCP::Server::Transports::StreamableHTTPTransport)
        allow(transport).to receive(:handle_request).and_return(
          [200, { 'Content-Type' => 'application/json' }, ['{"jsonrpc":"2.0","id":1,"result":{}}']]
        )
        server = instance_double(MCP::Server, transport: transport)
        allow(Rails.application.config.x).to receive(:dhan_mcp_server).and_return(server)
        body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        expect(transport).to have_received(:handle_request).with(instance_of(Rack::Request))
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
        # Transport returns simple error body for parse failures
        expect(json['error']).to eq('Invalid JSON')
      end
    end

    context 'when body is whitespace-only' do
      it 'returns 400 from transport parse error' do
        post '/mcp', params: "   \n\t  ",
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('Invalid JSON')
      end
    end

    context 'when body is invalid JSON' do
      let(:transport) do
        instance_double(MCP::Server::Transports::StreamableHTTPTransport).tap do |t|
          allow(t).to receive(:handle_request).and_return(
            [200, { 'Content-Type' => 'application/json' },
             ['{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error"}}']]
          )
        end
      end

      before do
        server = instance_double(MCP::Server, transport: transport)
        allow(Rails.application.config.x).to receive(:dhan_mcp_server).and_return(server)
      end

      it 'forwards body to transport and returns transport response' do
        body = 'not valid json'
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to have_key('error')
        expect(transport).to have_received(:handle_request).with(instance_of(Rack::Request))
      end
    end

    context 'when transport raises' do
      before do
        transport = instance_double(MCP::Server::Transports::StreamableHTTPTransport)
        allow(transport).to receive(:handle_request).and_raise(StandardError.new('server exploded'))
        server = instance_double(MCP::Server, transport: transport)
        allow(Rails.application.config.x).to receive(:dhan_mcp_server).and_return(server)
      end

      it 'returns 500 and is handled by ApplicationController' do
        post '/mcp', params: '{"jsonrpc":"2.0","id":1}',
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:internal_server_error)
        expect(response.parsed_body['error']).to eq('Internal server error')
      end
    end

    context 'when body is present and valid' do
      let(:transport) do
        instance_double(MCP::Server::Transports::StreamableHTTPTransport).tap do |t|
          allow(t).to receive(:handle_request).and_return(
            [200, { 'Content-Type' => 'application/json' },
             ['{"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"ok"}]}}']]
          )
        end
      end

      before do
        server = instance_double(MCP::Server, transport: transport)
        allow(Rails.application.config.x).to receive(:dhan_mcp_server).and_return(server)
      end

      it 'forwards body to transport and returns its response' do
        body = { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json
        post '/mcp', params: body,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq('application/json')
        expect(response.body).to include('"jsonrpc":"2.0"')
        expect(transport).to have_received(:handle_request).with(instance_of(Rack::Request))
      end
    end

    context 'with real transport (integration)' do
      it 'returns 406 when Accept header omits required types' do
        post '/mcp', params: { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_AUTH)
        expect(response).to have_http_status(:not_acceptable)
      end

      it 'returns 200 and tools/list result with valid Accept header' do
        post '/mcp', params: { jsonrpc: '2.0', id: 1, method: 'tools/list' }.to_json,
                     headers: { 'Content-Type' => 'application/json' }.merge(MCP_ACCEPT).merge(MCP_AUTH)
        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['jsonrpc']).to eq('2.0')
        expect(json['result']).to have_key('tools')
      end
    end
  end

  describe 'GET /mcp' do
    it 'returns 405 Method Not Allowed (stateless transport)' do
      get '/mcp', headers: MCP_ACCEPT.merge(MCP_AUTH)
      expect(response).to have_http_status(:method_not_allowed)
    end
  end
end
