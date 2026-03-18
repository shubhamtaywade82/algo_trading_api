# frozen_string_literal: true

class McpController < ApplicationController
  MCP_MAX_BODY_SIZE = 1_000_000 # 1 MB

  before_action :authenticate_mcp_request, only: [:handle]
  before_action :authenticate_debug_request, only: [:debug_handle]
  before_action :reject_oversized_body

  def handle
    return head :method_not_allowed if request.get?

    raw = request.body.read
    return render json: mcp_error(-32_700, 'Parse error', 'Request body is required'), status: :bad_request if raw.blank?

    request_body = JSON.parse(raw)
  rescue JSON::ParserError
    render json: mcp_error(-32_700, 'Parse error', 'Invalid JSON'), status: :bad_request
  else
    response = run_mcp_dispatch(request_body)
    return head :ok if response.nil?

    render json: response
  end

  def debug_handle
    return head :method_not_allowed if request.get?

    raw = request.body.read
    return render json: mcp_error(-32_700, 'Parse error', 'Request body is required'), status: :bad_request if raw.blank?

    request_body = JSON.parse(raw)
  rescue JSON::ParserError
    render json: mcp_error(-32_700, 'Parse error', 'Invalid JSON'), status: :bad_request
  else
    response = run_mcp_dispatch(request_body, registry: Mcp::DebugToolRegistry)
    return head :ok if response.nil?

    render json: response
  end

  private

  def run_mcp_dispatch(req, registry: Mcp::ToolRegistry)
    if req['id'].nil? && req.key?('method')
      handle_notification(req)
      return nil
    end

    Mcp::Dispatcher.call(req, registry: registry)
  rescue StandardError => e
    {
      jsonrpc: '2.0',
      id: req['id'],
      error: { code: -32_603, message: e.message }
    }
  end

  def handle_notification(req)
    Mcp::Dispatcher.call(req)
  end

  def authenticate_mcp_request
    expected = ENV.fetch('MCP_ACCESS_TOKEN', nil)
    if expected.blank?
      render json: mcp_error(-32_503, 'Service Unavailable', 'MCP_ACCESS_TOKEN must be set'), status: :service_unavailable
      return
    end

    token = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
    return if ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: mcp_error(-32_001, 'Unauthorized', 'Invalid or missing MCP access token'), status: :unauthorized
  end

  def authenticate_debug_request
    expected = ENV.fetch('MCP_DEBUG_TOKEN', ENV.fetch('MCP_ACCESS_TOKEN', nil))
    if expected.blank?
      render json: mcp_error(-32_503, 'Service Unavailable', 'MCP_DEBUG_TOKEN or MCP_ACCESS_TOKEN must be set'), status: :service_unavailable
      return
    end

    token = request.authorization.to_s.sub(/\ABearer\s+/i, '').strip
    return if ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: mcp_error(-32_001, 'Unauthorized', 'Invalid or missing debug access token'), status: :unauthorized
  end

  def reject_oversized_body
    return if request.content_length.blank? || request.content_length <= MCP_MAX_BODY_SIZE

    render json: mcp_error(-32_600, 'Invalid request', 'Request body exceeds maximum size'), status: :payload_too_large
  end

  def mcp_error(code, message, data = nil)
    { jsonrpc: '2.0', id: nil, error: { code: code, message: message, data: data }.compact }
  end
end
