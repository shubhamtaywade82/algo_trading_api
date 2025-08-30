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

      # Calculate strike step (interval)
      strike_step = calculate_strike_step(atm_index)

      {
        atm: option_data_for_strike(atm_strike),
        otm_call: option_data_for_strike(@strikes.detect { |s| s > @spot }),
        itm_call: option_data_for_strike(@strikes.reverse.detect { |s| s < @spot }),
        otm_put: option_data_for_strike(@strikes.reverse.detect { |s| s < @spot }),
        itm_put: option_data_for_strike(@strikes.detect { |s| s > @spot })
      }
      {
        atm: option_data_for_strike(atm_strike),
        otm_call: option_data_for_strike(@strikes[atm_index + 1]),
        itm_call: option_data_for_strike(@strikes[atm_index - 1]),
        otm_put: option_data_for_strike(@strikes[atm_index - 1]),
        itm_put: option_data_for_strike(@strikes[atm_index + 1])
      }
    end

    private

    def calculate_strike_step(atm_index)
      return 50 if @strikes.size < 2 # Default step if we can't calculate
      
      # Try to calculate step from adjacent strikes
      if atm_index > 0 && atm_index < @strikes.size - 1
        step1 = @strikes[atm_index] - @strikes[atm_index - 1]
        step2 = @strikes[atm_index + 1] - @strikes[atm_index]
        (step1 + step2) / 2
      elsif atm_index > 0
        @strikes[atm_index] - @strikes[atm_index - 1]
      elsif atm_index < @strikes.size - 1
        @strikes[atm_index + 1] - @strikes[atm_index]
      else
        50 # Fallback default
      end
    end

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
