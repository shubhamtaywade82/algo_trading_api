# frozen_string_literal: true

module Strategies
  module Index
    class IntradayStrategy < BaseStrategy
      def execute
        option_chain = fetch_option_chain
        strike_price = Option::ChainAnalyzer.new(option_chain).select_best_strike
        place_option_order(strike_price)
      end

      private

      def fetch_option_chain
        OptionChainService.fetch(alert.ticker, alert.exchange)
      end

      def place_option_order(strike_price)
        instrument = find_instrument_for_strike(strike_price)
        funds = fetch_funds
        quantity = calculate_option_quantity(instrument, funds)

        order_params = build_order_params(instrument, quantity, strike_price)
        response = OrderManager.place(order_params)

        Order.create!(response) if response.success?
      end

      def find_instrument_for_strike(strike_price)
        InstrumentRepository.find_by_strike(alert.ticker, strike_price)
      end

      def fetch_funds
        FundsService.fetch_funds[:availabelBalance]
      end

      def calculate_option_quantity(instrument, funds)
        lot_size = instrument.lot_size
        max_funds = funds * 0.3
        [(max_funds / instrument.last_price).floor, lot_size].max
      end

      def build_order_params(instrument, quantity, strike_price)
        {
          dhanClientId: ENV.fetch('DHAN_CLIENT_ID', nil),
          transactionType: alert.action.upcase,
          productType: 'INTRADAY',
          orderType: alert.order_type.upcase,
          securityId: instrument.security_id,
          quantity: quantity,
          price: strike_price
        }
      end
    end
  end
end
