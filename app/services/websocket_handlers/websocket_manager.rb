# frozen_string_literal: true

class WebSocketManager
  def initialize(url, auth_message)
    @url = url
    @auth_message = auth_message
    @websocket = nil
  end

  def connect
    EM.run do
      @websocket = Faye::WebSocket::Client.new(@url)

      @websocket.on(:open) { |event| handle_open(event) }
      @websocket.on(:message) { |event| handle_message(event) }
      @websocket.on(:close) { |event| handle_close(event) }
      @websocket.on(:error) { |event| handle_error(event) }
    end
  end

  def send_message(message)
    @websocket&.send(message.to_json)
  end

  private

  def handle_open(_event)
    Rails.logger.info('WebSocket connection opened.')
    send_message(@auth_message)
  end

  def handle_message(event)
    # Process incoming WebSocket messages
  end

  def handle_close(event)
    Rails.logger.warn("WebSocket connection closed: #{event.code} - #{event.reason}")
    EM.stop
  end

  def handle_error(event)
    Rails.logger.error("WebSocket error: #{event.message}")
  end
end
