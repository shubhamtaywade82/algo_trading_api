# frozen_string_literal: true

class TrailingStopLossEvent
  def self.trigger(order_id, new_stop_loss)
    ActiveSupport::Notifications.instrument('order.stop_loss_updated', order_id: order_id, new_stop_loss: new_stop_loss)
  end
end
