# frozen_string_literal: true

class McpController < ApplicationController
  MCP_MAX_BODY_SIZE = 1_000_000 # 1 MB

  before_action :authenticate_mcp_request
  before_action :reject_oversized_body

  def index
    server = Rails.application.config.x.dhan_mcp_server
    transport = server.transport

    if transport
      serve_streamable_http(transport)
    else
      serve_legacy_json(server)
    end
  end

  private

  def serve_streamable_http(transport)
    rack_request = Rack::Request.new(request.env)
    status, headers, body_parts = transport.handle_request(rack_request)
    headers.each { |k, v| response.headers[k] = v }
    body = body_parts.is_a?(Array) && body_parts.any? ? body_parts.first : nil
    render status: status, body: body, content_type: headers['Content-Type']
  end

  def serve_legacy_json(server)
    raw = request.body.read
    if raw.blank?
      return render json: mcp_error(-32_700, 'Parse error', 'Request body is required'), status: :bad_request
    end

    body = server.handle_json(raw)
    render body: body, content_type: 'application/json'
  end

  def authenticate_mcp_request
    expected = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    unless expected.present?
      render json: mcp_error(-32_503, 'Service Unavailable', 'MCP_ACCESS_TOKEN must be set'), status: :service_unavailable
      return
    end

    token = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
    return if ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: mcp_error(-32_001, 'Unauthorized', 'Invalid or missing MCP access token'), status: :unauthorized
  end

  def reject_oversized_body
    return if request.content_length.blank? || request.content_length <= MCP_MAX_BODY_SIZE

    render json: mcp_error(-32_600, 'Invalid request', 'Request body exceeds maximum size'), status: :payload_too_large
  end

  def mcp_error(code, message, data = nil)
    { jsonrpc: '2.0', id: nil, error: { code: code, message: message, data: data }.compact }
  end
end
