# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for executing a specific tool via MCP.
    class CallTool
      class << self
        private

        def normalize_args(args)
          raise ArgumentError, 'Expected Hash' unless args.is_a?(Hash)

          args.deep_symbolize_keys
        end
      end

      def self.call(req, registry: ToolRegistry)
        params = req['params'] || {}
        name   = params['name']
        args   = normalize_args(params['arguments'] || {})

        tool = registry.tools.find { |t| t.name == name }
        raise "Unknown tool: #{name}" unless tool

        Rails.logger.info("[MCP] Tool=#{name} Args=#{args.inspect}")

        result = tool.execute(args)
        is_error =
          result.is_a?(Hash) &&
          result.key?(:error) &&
          result[:error].present?

        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            structuredContent: result,
            content: [{ type: 'text', text: result.to_json }],
            isError: is_error
          }
        }
      rescue StandardError => e
        Rails.logger.error("[MCP ERROR] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace.present?
        {
          jsonrpc: '2.0',
          id: req['id'],
          result: {
            structuredContent: { error: e.message },
            content: [{ type: 'text', text: { error: e.message }.to_json }],
            isError: true
          }
        }
      end
    end
  end
end
