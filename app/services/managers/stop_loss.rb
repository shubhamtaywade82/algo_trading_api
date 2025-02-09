# frozen_string_literal: true

module Managers
  class StopLoss < Base
    def self.update(position)
      execute_safely do
        new(position).adjust
      end
    end

    def initialize(position)
      @position = position
    end

    def adjust
      new_stop_loss = calculate_adaptive_stop_loss
      return unless new_stop_loss > @position['costPrice'].to_f

      update_stop_loss(new_stop_loss)
    end

    private

    def calculate_adaptive_stop_loss
      Managers::ATR.calculate(@position) * 2.5
    end

    def update_stop_loss(new_stop_loss)
      Dhanhq::API::Orders.modify(@position['orderId'], { triggerPrice: new_stop_loss })
    end
  end
end
