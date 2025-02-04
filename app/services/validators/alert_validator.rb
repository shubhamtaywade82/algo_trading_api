# frozen_string_literal: true

module Validators
  class AlertValidator
    include ActiveModel::Model

    attr_accessor :ticker, :instrument_type, :action, :order_type, :current_position,
                  :previous_position, :current_price, :high, :low, :volume, :time,
                  :stop_loss, :take_profit, :trailing_stop_loss, :strategy_name, :strategy_id

    validates :ticker, :instrument_type, :action, :order_type, :strategy_name, :strategy_id, presence: true
    validates :instrument_type, inclusion: { in: %w[stock index] }
    validates :action, inclusion: { in: %w[buy sell] }
    validates :order_type, inclusion: { in: %w[market limit stop] }
    validates :current_price, :stop_loss, :take_profit, numericality: { greater_than: 0 }
    validates :volume, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :time, presence: true

    def initialize(params = {})
      super(params.permit(:ticker, :instrument_type, :action, :order_type, :current_position,
                          :previous_position, :current_price, :high, :low, :volume, :time,
                          :stop_loss, :take_profit, :trailing_stop_loss, :strategy_name, :strategy_id))
    end
  end
end
