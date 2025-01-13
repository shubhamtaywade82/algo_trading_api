# frozen_string_literal: true

class LiveOrderWebSocket < BaseWebSocket
  def handle_message(data)
    order_data = JSON.parse(data)
    OrderProcessor.process(order_data)
  rescue JSON::ParserError => e
    ErrorLogger.log_error('Failed to parse WebSocket message', e)
  end
end
