# frozen_string_literal: true

module TradingServices
  class BaseTradingService < ApplicationService
    attr_reader :symbol_name, :exchange, :segment, :timeframe

    def initialize(symbol_name, exchange, segment, timeframe: 'daily')
      @symbol_name = symbol_name
      @exchange = exchange
      @segment = segment
      @timeframe = timeframe
    end

    def execute_trade
      raise NotImplementedError, 'Subclasses must implement `execute_trade`'
    end

    def call
      execute_trade
    end

    protected

    def levels
      @levels ||= instrument.levels
                            .where(timeframe: @timeframe)
                            .order(period_start: :desc)
                            .first
    end

    def determine_trade_action(ltp, levels)
      if ltp <= levels.demand_zone
        :buy
      elsif ltp >= levels.supply_zone
        :sell
      else
        :neutral
      end
    end

    def place_order(transaction_type, security_id, quantity)
      result = Orders::OrdersService.new.call({
                                                correlation_id: SecureRandom.uuid,
                                                transactionType: transaction_type,
                                                exchangeSegment: instrument.exchange_segment,
                                                productType: product_type,
                                                order_type: 'MARKET',
                                                securityId: security_id,
                                                quantity: quantity,
                                                price: nil,
                                                triggerPrice: nil
                                              })

      handle_order_result(result)
    end

    def handle_order_result(result)
      if result.success?
        Rails.logger.debug { "Order placed successfully: #{result.success}" }
      else
        Rails.logger.debug { "Order placement failed: #{result.failure}" }
      end
    end

    def product_type
      'INTRADAY' # Default product type, can be overridden in subclasses
    end

    private

    def instrument
      @instrument ||= Instrument.nse.segment_index.find_by(symbol_name: symbol_name).tap do |inst|
        raise "Instrument not found for #{symbol_name} in #{segment}" unless inst
      end
    end
  end
end
