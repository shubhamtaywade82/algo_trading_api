# frozen_string_literal: true

module Orders
  class IntradayOrderManager < Orders::BaseOrderManager
    def call
      instrument = fetch_instrument
      funds = fetch_funds
      margin = fetch_margin_details(instrument[:id])
      quantity = calculate_quantity(funds, margin, @alert.current_price)

      place_order(order_params(instrument[:id], quantity))
    end

    private

    def order_params(instrument_id, quantity)
      {
        dhanClientId: ENV.fetch('DHAN_CLIENT_ID', nil),
        transactionType: @alert.action.upcase,
        productType: 'INTRADAY',
        orderType: @alert.order_type.upcase,
        securityId: instrument_id,
        quantity: quantity,
        price: @alert.limit_price
      }
    end

    def fetch_margin_details(instrument_id)
      # Call Margin Calculator API
    end
  end
end
