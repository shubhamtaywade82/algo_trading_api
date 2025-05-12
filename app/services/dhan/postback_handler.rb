module Dhan
  class PostbackHandler < ApplicationService
    def initialize(payload)
      @data = payload.with_indifferent_access
    end

    def call
      order = Order.find_by(dhan_order_id: @data[:orderId])

      unless order
        Rails.logger.warn "[Postback] Order not found for dhan_order_id=#{@data[:orderId]}"
        return
      end

      order.update!(
        order_status: @data[:orderStatus],
        filled_qty: @data[:quantity],
        average_traded_price: @data[:price].to_f.presence,
        updated_at: begin
          Time.zone.parse(@data[:updateTime])
        rescue StandardError
          Time.zone.now
        end
      )

      PostbackLog.create!(
        order_id: order.id,
        dhan_order_id: order.dhan_order_id,
        event: @data[:orderStatus],
        payload: @data
      )

      maybe_log(order)
      maybe_notify(order)
    end

    private

    def maybe_log(order)
      Rails.logger.info "[Postback] Order ##{order.id} (#{order.dhan_order_id}) updated to #{order.order_status}"
    end

    def maybe_notify(order)
      return unless order.order_status == 'REJECTED'

      # Optional: alert/notify
      Rails.logger.warn "[Postback] 🚨 Order #{order.id} was REJECTED"
    end
  end
end
