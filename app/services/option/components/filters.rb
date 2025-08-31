# frozen_string_literal: true

module Option
  module Components
    class Filters
      def initialize(ctx) = @ctx = ctx

      def filtered_strikes(signal_type:)
        side = signal_type.to_sym
        atm  = @ctx.atm_strike
        return [] unless atm

        picks = @ctx.oc[:oc].filter_map do |strike_str, data|
          opt = data[side]
          next unless opt

          iv    = opt['implied_volatility'].to_f
          price = opt['last_price'].to_f
          next if iv.zero? || price.zero?

          strike = strike_str.to_f
          delta  = opt.dig('greeks', 'delta').to_f.abs

          min_delta = @ctx.min_delta_for(strike)
          next if delta < min_delta

          next if deep_itm?(strike, signal_type, atm)
          next if deep_otm?(strike, signal_type, atm)

          next unless within_enhanced_atm?(strike, signal_type, atm)

          build_strike_data(strike, opt, data['volume'])
        end

        picks.sort_by { |s| (s[:strike_price] - atm).abs }
      end

      private

      def within_enhanced_atm?(strike, signal_type, atm)
        base_range = @ctx.atm_range_pct * @ctx.spot
        case signal_type
        when :ce then strike >= atm && strike <= (atm + base_range)
        when :pe then strike <= atm && strike >= (atm - base_range)
        else strike >= (atm - base_range) && strike <= (atm + base_range)
        end
      end

      def deep_itm?(strike, signal_type, atm)
        if signal_type == :ce
          strike > atm * 1.2
        elsif signal_type == :pe
          strike < atm * 0.8
        end
      end

      def deep_otm?(strike, signal_type, atm)
        if signal_type == :ce
          strike < atm * 0.8
        elsif signal_type == :pe
          strike > atm * 1.2
        end
      end

      def build_strike_data(strike_price, opt, volume)
        {
          strike_price: strike_price,
          last_price: opt['last_price'].to_f,
          iv: opt['implied_volatility'].to_f,
          oi: opt['oi'].to_i,
          volume: volume.to_i,
          greeks: {
            delta: opt.dig('greeks', 'delta').to_f,
            gamma: opt.dig('greeks', 'gamma').to_f,
            theta: opt.dig('greeks', 'theta').to_f,
            vega: opt.dig('greeks', 'vega').to_f
          },
          previous_close_price: opt['previous_close_price'].to_f,
          previous_oi: opt['previous_oi'].to_i,
          previous_volume: opt['previous_volume'].to_i,
          price_change: opt['last_price'].to_f - opt['previous_close_price'].to_f,
          oi_change: opt['oi'].to_i - opt['previous_oi'].to_i,
          volume_change: volume.to_i - opt['previous_volume'].to_i,
          bid_ask_spread: (opt['top_ask_price'].to_f - opt['top_bid_price'].to_f).abs
        }
      end
    end
  end
end
