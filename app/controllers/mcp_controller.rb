# frozen_string_literal: true

class McpController < ApplicationController
  def index
    raw = request.body.read
    if raw.blank?
      return render json: {
        jsonrpc: '2.0',
        id: nil,
        error: { code: -32_700, message: 'Parse error', data: 'Request body is required' }
      }, status: :bad_request
    end
    server = Rails.application.config.x.dhan_mcp_server
    body = server.handle_json(raw)
    render body: body, content_type: 'application/json'
  end
end
