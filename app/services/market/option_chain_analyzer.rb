# frozen_string_literal: true

module Market
  class OptionChainAnalyzer
    def initialize(option_chain_data, spot_price)
      @chain = option_chain_data
      @spot_price = spot_price
    end

    def extract_strikes
      strikes = @chain["optionDetailsList"] || []

      # Find ATM strike
      atm = strikes.min_by { |s| (s["strikePrice"].to_f - @spot_price).abs }

      {
        atm: build_data(atm),
        otm_call: build_data(
          strikes.find { |s| s["strikePrice"].to_f > @spot_price }
        ),
        itm_call: build_data(
          strikes.reverse.find { |s| s["strikePrice"].to_f < @spot_price }
        ),
        otm_put: build_data(
          strikes.reverse.find { |s| s["strikePrice"].to_f < @spot_price }
        ),
        itm_put: build_data(
          strikes.find { |s| s["strikePrice"].to_f > @spot_price }
        )
      }
    end

    private

    def build_data(strike)
      return nil unless strike

      {
        strike: strike["strikePrice"],
        call: strike["call"],
        put: strike["put"]
      }
    end
  end
end