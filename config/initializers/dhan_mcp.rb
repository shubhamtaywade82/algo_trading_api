# frozen_string_literal: true

Rails.application.config.after_initialize do
  server = DhanMcpService.build_server
  transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
  server.transport = transport
  Rails.application.config.x.dhan_mcp_server = server
end
