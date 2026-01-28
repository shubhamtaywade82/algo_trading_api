# frozen_string_literal: true

Rails.application.config.after_initialize do
  Rails.application.config.x.dhan_mcp_server = DhanMcpService.build_server
end
