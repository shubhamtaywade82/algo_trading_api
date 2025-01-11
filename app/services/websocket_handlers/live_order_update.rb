# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'

class LiveOrderUpdate
  def initialize
    @url = 'wss://api-order-update.dhan.co'
    @auth_message = {
      LoginReq: {
        MsgCode: 42,
        ClientId: ENV.fetch('DHAN_CLIENT_ID'),
        Token: ENV.fetch('DHAN_ACCESS_TOKEN')
      },
      UserType: 'SELF'
    }
  end

  def connect
    EM.run do
      @ws = Faye::WebSocket::Client.new(@url)

      @ws.on(:open) do |_event|
        authenticate
        Rails.logger.info '[LiveOrderUpdate] WebSocket connection established.'
      end

      @ws.on(:message) do |event|
        handle_message(event.data)
      end

      @ws.on(:close) do |event|
        Rails.logger.warn "[LiveOrderUpdate] WebSocket connection closed: Code=#{event.code}, Reason=#{event.reason}"
        EM.stop
      end

      @ws.on(:error) do |event|
        Rails.logger.error "[LiveOrderUpdate] WebSocket encountered an error: #{event.message}"
      end
    end
  end

  private

  def authenticate
    if @ws
      @ws.send(@auth_message.to_json)
      Rails.logger.info '[LiveOrderUpdate] Authentication message sent.'
    else
      Rails.logger.error '[LiveOrderUpdate] WebSocket connection not established. Cannot authenticate.'
    end
  end

  def handle_message(data)
    parsed_data = JSON.parse(data)

    # Ensure the message type is `order_alert`
    if parsed_data['Type'] == 'order_alert'
      process_order_update(parsed_data['Data'])
    else
      Rails.logger.info "[LiveOrderUpdate] Unhandled message type: #{parsed_data['Type']}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[LiveOrderUpdate] JSON parsing failed: #{e.message}. Raw data: #{data}"
  rescue StandardError => e
    Rails.logger.error "[LiveOrderUpdate] Error processing message: #{e.message}. Data: #{data}"
  end

  def process_order_update(order_data)
    # Validate presence of required fields
    required_fields = %w[OrderNo Status Symbol Price TradedQty]
    missing_fields = required_fields - order_data.keys

    if missing_fields.any?
      Rails.logger.warn "[LiveOrderUpdate] Missing required fields: #{missing_fields.join(', ')}. Data: #{order_data}"
      return
    end

    # Example: Update the order in the database
    order = Order.find_by(dhan_order_id: order_data['OrderNo'])
    if order
      order.update(
        dhan_status: order_data['Status'],
        traded_price: order_data['TradedPrice'],
        remaining_quantity: order_data['RemainingQuantity'],
        traded_quantity: order_data['TradedQty'],
        last_updated_time: order_data['LastUpdatedTime']
      )
      Rails.logger.info "[LiveOrderUpdate] Order updated successfully: OrderNo=#{order_data['OrderNo']}"
    else
      Rails.logger.warn "[LiveOrderUpdate] Order not found: OrderNo=#{order_data['OrderNo']}"
    end
  end
end
