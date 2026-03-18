# frozen_string_literal: true

module Mcp
  # Routes JSON-RPC requests to MCP lifecycle and tool handlers.
  # Spec: lifecycle (initialize, notifications/initialized), tools/list, tools/call.
  class Dispatcher
    def self.call(req, registry: ToolRegistry)
      method = req['method'].to_s
      case method
      when 'initialize'
        Handlers::Initialize.call(req)
      when 'notifications/initialized'
        nil
      when 'tools/list'
        Handlers::ListTools.call(req, registry: registry)
      when 'tools/call'
        Handlers::CallTool.call(req, registry: registry)
      else
        {
          jsonrpc: '2.0',
          id: req['id'],
          error: { code: -32_601, message: 'Method not found' }
        }
      end
    end
  end
end
