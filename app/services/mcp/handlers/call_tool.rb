# frozen_string_literal: true

module Mcp
  module Handlers
    # Handler for executing a specific tool via MCP.
    class CallTool
      class << self
        private

        def normalize_args(args)
          raise ArgumentError, 'Expected Hash' unless args.is_a?(Hash)

          payload = args.with_indifferent_access
          payload = payload[:params].merge(payload.except(:params, :server_context)) if payload[:params].is_a?(Hash)

          payload.except(:server_context).deep_symbolize_keys
        end

        def extract_args(params)
          return {} if params.blank?

          if params.key?('arguments') || params.key?(:arguments)
            normalize_args(params['arguments'] || params[:arguments] || {})
          else
            normalize_args(params.except('name', :name, 'server_context', :server_context))
          end
        end

        def extract_call_params(req)
          return {} unless req.is_a?(Hash)

          if req['params'].is_a?(Hash) || req[:params].is_a?(Hash)
            req['params'] || req[:params]
          elsif req['arguments'].is_a?(Hash) || req[:arguments].is_a?(Hash)
            req['arguments'] || req[:arguments]
          else
            req.except('jsonrpc', 'id', 'method', :jsonrpc, :id, :method)
          end
        end
      end

      def self.call(req, registry: ToolRegistry)
        params = extract_call_params(req)
        name   = params['name'] || params[:name]
        args   = extract_args(params)

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
