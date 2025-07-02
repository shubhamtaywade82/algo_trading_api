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

      {
        atm: option_data_for_strike(atm_strike),
        otm_call: option_data_for_strike(@strikes.detect { |s| s > @spot }),
        itm_call: option_data_for_strike(@strikes.reverse.detect { |s| s < @spot }),
        otm_put: option_data_for_strike(@strikes.reverse.detect { |s| s < @spot }),
        itm_put: option_data_for_strike(@strikes.detect { |s| s > @spot })
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
