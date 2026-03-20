# frozen_string_literal: true

module Mcp
  module Tools
    # Shared argument normalization/validation for MCP tools.
    module ExecutionHelpers
      private

      def normalize_args!(tool_name, args)
        raise ArgumentError, 'Expected Hash' unless args.is_a?(Hash)

        normalized_args = args.deep_symbolize_keys
        Rails.logger.info("[MCP] Tool=#{tool_name} Args=#{normalized_args.inspect}")
        normalized_args
      end
    end
  end
end
