# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for the MCP initialize request.
    class Initialize
      PROTOCOL_VERSION = '2024-11-05'
      SERVER_NAME     = 'algo-trading-api'
      SERVER_VERSION  = '1.0.0'

      def self.call(req)
        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            protocolVersion: PROTOCOL_VERSION,
            capabilities: {
              tools: { listChanged: false },
              resources: {},
              prompts: {}
            },
            serverInfo: {
              name: SERVER_NAME,
              version: SERVER_VERSION,
              description: 'Algorithmic trading MCP server — DhanHQ v2, options, positions, orders'
            }
          }
        }
      end
    end
  end
end
