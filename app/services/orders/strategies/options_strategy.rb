module Orders
  module Strategies
    class OptionsStrategy < BaseStrategy
      def execute
        raise "Lot size not found for #{alert[:ticker]}" unless instrument.lot_size

        place_order(
          dhan_order_params.merge(
            productType: default_product_type,
            strikePrice: calculate_strike_price(alert[:current_price]),
            optionType: determine_option_type(alert[:action].upcase),
            expiryDate: nearest_expiry_date
          )
        )
      end

      private

      def default_product_type
        Dhanhq::Constants::CNC # Options are typically delivery
      end

      def calculate_strike_price(price)
        step = instrument.tick_size || 50 # Default to 50 if tick size is missing
        (price / step).round * step
      end

      def determine_option_type(action)
        case action
        when Dhanhq::Constants::BUY then "CE" # Call
        when Dhanhq::Constants::SELL then "PE" # Put
        else
          raise "Invalid action for options: #{action}"
        end
      end

      def nearest_expiry_date
        Instrument.where(
          underlying_symbol: instrument.underlying_symbol,
          expiry_flag: instrument.expiry_flag
        ).where("sm_expiry_date >= ?", Date.today)
         .order(:sm_expiry_date)
         .limit(1)
         .pluck(:sm_expiry_date)
         .first
      end
    end
  end
end
