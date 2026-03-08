# frozen_string_literal: true

module DhanMcp
  # Base class for DhanHQ MCP tool definitions.
  class BaseTool
    def initialize(server, service)
      @server = server
      @service = service
    end

    def self.define(server, service)
      new(server, service).define
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
  end
end
