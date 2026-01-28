# frozen_string_literal: true

module AlertProcessors
  # Builds Dhan order payloads for index options (legacy single-leg or super/bracket).
  class IndexOrderPayloadBuilder
    SIGNAL_TO_SIDE = {
      'long_entry' => 'BUY',
      'short_entry' => 'BUY',
      'long_exit' => 'SELL',
      'short_exit' => 'SELL'
    }.freeze

    def self.build_legacy(derivative:, quantity:, signal_type:, order_type:)
      {
        transaction_type: SIGNAL_TO_SIDE.fetch(signal_type),
        order_type: order_type.to_s.upcase,
        product_type: 'MARGIN',
        validity: 'DAY',
        security_id: derivative.security_id,
        exchange_segment: derivative.exchange_segment,
        quantity: quantity
      }
    end

    def self.build_super(derivative:, quantity:, signal_type:, order_type:, entry_price:, stop_loss:, target:, trailing_jump:)
      {
        transaction_type: SIGNAL_TO_SIDE.fetch(signal_type),
        exchange_segment: derivative.exchange_segment,
        product_type: 'MARGIN',
        order_type: order_type.to_s.upcase,
        security_id: derivative.security_id,
        quantity: quantity,
        price: entry_price.to_f,
        target_price: target,
        stop_loss_price: stop_loss,
        trailing_jump: trailing_jump
      }
    end
  end
end
