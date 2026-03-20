# frozen_string_literal: true

module DhanMcp
  # Base class for DhanHQ MCP tool definitions.
  class BaseTool
    def initialize(server, service)
      @server = server
      @service = service
    end

    def self.define(server, service)
      new(server, service)
    end

    protected

    def dhan(fmt, &)
      @service.send(:dhan, fmt, &)
    end

    def resolve_instrument(exchange_segment, symbol)
      @service.send(:resolve_instrument, exchange_segment, symbol)
    end

    def validate(tool_name, args)
      DhanMcp::ArgumentValidator.validate(tool_name, args)
    end

    def normalized_args(params: nil, **kwargs)
      payload = params.is_a?(Hash) ? params : kwargs
      DhanMcp::ArgumentValidator.symbolize(payload).except(:server_context)
    end
  end
end
