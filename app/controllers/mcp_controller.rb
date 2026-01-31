# frozen_string_literal: true

class McpController < ApplicationController
  MCP_MAX_BODY_SIZE = 1_000_000 # 1 MB

  before_action :authenticate_mcp_request, if: :mcp_auth_required?
  before_action :reject_oversized_body

  def index
    raw = request.body.read
    return render json: mcp_error(-32_700, 'Parse error', 'Request body is required'), status: :bad_request if raw.blank?

    server = Rails.application.config.x.dhan_mcp_server
    body = server.handle_json(raw)
    render body: body, content_type: 'application/json'
  end

  private

  def mcp_auth_required?
    ENV['MCP_ACCESS_TOKEN'].present?
  end

  def authenticate_mcp_request
    token = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
    expected = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)

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
