# frozen_string_literal: true

module Orders
  class Manager < ApplicationService
    def initialize(position, analysis)
      @position = position.with_indifferent_access
      @analysis = analysis
    end

    def call
      decision = Orders::RiskManager.call(@position, @analysis)

      if decision[:exit]
        merged = @analysis.merge(order_type: decision[:order_type]) if decision[:order_type]
        Orders::Executor.call(@position, decision[:exit_reason], merged || @analysis)
      elsif decision[:adjust]
        Orders::Adjuster.call(@position, decision[:adjust_params])
      end
    rescue StandardError => e
      Rails.logger.error("[Orders::Manager] Error for #{@position[:tradingSymbol]}: #{e.message}")
    end
  end
end
