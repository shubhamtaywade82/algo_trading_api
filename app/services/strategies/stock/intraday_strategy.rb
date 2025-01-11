# frozen_string_literal: true

module Strategies
  module Stock
    class IntradayStrategy < BaseStrategy
      def execute
        instrument = fetch_instrument
        mis_details = fetch_mis_details(instrument)
        funds = fetch_funds
        quantity = calculate_quantity(funds, mis_details, alert.current_price)

        order_params = build_order_params(instrument, quantity)
        response = OrderManager.place(order_params)

        Order.create!(response) if response.success?
      end

      private

      def fetch_instrument
        InstrumentRepository.find_by(symbol: alert.ticker)
      end

      def fetch_mis_details(instrument)
        instrument.mis_detail
      end

      def fetch_funds
        FundsService.fetch_funds[:availabelBalance]
      end

      def calculate_quantity(funds, mis_details, price)
        leverage = mis_details.mis_leverage || 1
        max_funds = funds * 0.3
        (max_funds / (price / leverage)).floor
      end

      def build_order_params(instrument, quantity)
        {
          dhanClientId: ENV.fetch('DHAN_CLIENT_ID', nil),
          transactionType: alert.action.upcase,
          productType: 'INTRADAY',
          orderType: alert.order_type.upcase,
          securityId: instrument.security_id,
          quantity: quantity,
          price: alert.limit_price
        }
      end
    end
  end
end
