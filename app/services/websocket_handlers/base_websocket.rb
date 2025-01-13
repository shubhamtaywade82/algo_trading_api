# frozen_string_literal: true

require 'faye/websocket'

class BaseWebSocket
  def initialize(url, auth_message)
    @url = url
    @auth_message = auth_message
    @websocket = nil
  end

  def connect
    EM.run do
      @websocket = Faye::WebSocket::Client.new(@url)
      setup_callbacks
    end
  end

  def send_message(message)
    @websocket&.send(message.to_json)
  end

  private

  def setup_callbacks
    @websocket.on(:open) { handle_open }
    @websocket.on(:message) { |event| handle_message(event.data) }
    @websocket.on(:close) { |event| handle_close(event) }
    @websocket.on(:error) { |event| handle_error(event) }
  end

  def handle_open
    send_message(@auth_message)
    Rails.logger.info('WebSocket connection opened.')
  end

  def handle_message(data)
    Rails.logger.info("Received message: #{data}")
  end

  def handle_close(event)
    Rails.logger.warn("WebSocket connection closed: #{event.code} - #{event.reason}")
    EM.stop
  end

  def handle_error(event)
    ErrorLogger.log_error('WebSocket error', event)
  end
end
