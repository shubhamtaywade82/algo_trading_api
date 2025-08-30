# frozen_string_literal: true

module Market
  class OptionChainAnalyzer
    def initialize(option_chain_data, spot_price)
      @spot = spot_price.to_f
      @chain_data = option_chain_data[:oc] || {}
      @strikes = @chain_data.keys.map(&:to_f).sort
    end

    def extract_data
      return nil if @chain_data.blank? || @strikes.blank?

      atm_strike = @strikes.min_by { |s| (s - @spot).abs }
      atm_index = @strikes.index(atm_strike)

      # Get adjacent strikes, handling boundary conditions
      otm_call_strike = @strikes[atm_index + 1] || atm_strike
      itm_call_strike = @strikes[atm_index - 1] || atm_strike
      otm_put_strike = itm_call_strike  # OTM put is same as ITM call
      itm_put_strike = otm_call_strike  # ITM put is same as OTM call

      {
        atm: option_data_for_strike(atm_strike),
        otm_call: option_data_for_strike(otm_call_strike),
        itm_call: option_data_for_strike(itm_call_strike),
        otm_put: option_data_for_strike(otm_put_strike),
        itm_put: option_data_for_strike(itm_put_strike)
      }
    end

    private

    def option_data_for_strike(strike)
      return nil unless strike && @chain_data[format('%.6f', strike)]

      node = @chain_data[format('%.6f', strike)]
      {
        strike: strike,
        call: node['ce'],
        put: node['pe']
      }
    end
  end
end