module Orders
  module Strategies
    class IntradayOptionsStrategy < BaseStrategy
      def execute
        strike_price = calculate_strike_price(alert[:current_price])
        option_type = determine_option_type(alert[:action].upcase)

        place_order(
          dhan_order_params.merge(
            productType: Dhanhq::Constants::INTRA,
            strikePrice: strike_price,
            optionType: option_type,
            expiryDate: nearest_expiry_date
          )
        )
      end

      private

      def calculate_strike_price(price)
        step = instrument.tick_size || 50
        (price / step).round * step
      end

      def determine_option_type(action)
        case action
        when Dhanhq::Constants::BUY then "CE" # Call Option
        when Dhanhq::Constants::SELL then "PE" # Put Option
        else
          raise "Invalid action: #{action}"
        end
      end

      def nearest_expiry_date
        Derivative.where(instrument: instrument)
                  .where("expiry_date >= ?", Date.today)
                  .order(:expiry_date)
                  .limit(1)
                  .pluck(:expiry_date)
                  .first
      end
    end
  end
end
