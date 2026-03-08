# frozen_string_literal: true

module Option
  module ChainAnalyzerModules
    # Filtering logic for strikes in ChainAnalyzer
    module StrikeFiltering
      def gather_filtered_strikes(signal_type)
        side = signal_type.to_sym
        atm_strike = determine_atm_strike
        return [] unless atm_strike

        strikes = @option_chain[:oc].filter_map do |strike_str, data|
          option = data[side]
          next unless option

          # Skip strikes with no valid IV or price
          next if option['implied_volatility'].to_f.zero? || option['last_price'].to_f.zero?

          strike_price = strike_str.to_f
          delta = option.dig('greeks', 'delta').to_f.abs

          # distance-aware delta floor
          min_delta = min_delta_for(strike_price, atm_strike)
          next if delta < min_delta

          # Skip deep ITM/OTM
          next if deep_itm_strike?(strike_price, signal_type)
          next if deep_otm_strike?(strike_price, signal_type)

          # Enhanced ATM range (keeps grid-awareness)
          next unless within_enhanced_atm_range?(strike_price, signal_type)

          build_strike_data(strike_price, option, data['volume'])
        end

        # Prefer proximity to ATM (still sorted by closeness first)
        strikes.sort_by { |s| (s[:strike_price] - atm_strike).abs }
      end

      def build_strike_data(strike_price, option, volume)
        {
          strike_price: strike_price,
          last_price: option['last_price'].to_f,
          iv: option['implied_volatility'].to_f,
          oi: option['oi'].to_i,
          volume: volume.to_i,
          greeks: {
            delta: option.dig('greeks', 'delta').to_f,
            gamma: option.dig('greeks', 'gamma').to_f,
            theta: option.dig('greeks', 'theta').to_f,
            vega: option.dig('greeks', 'vega').to_f
          },
          previous_close_price: option['previous_close_price'].to_f,
          previous_oi: option['previous_oi'].to_i,
          previous_volume: option['previous_volume'].to_i,
          price_change: option['last_price'].to_f - option['previous_close_price'].to_f,
          oi_change: option['oi'].to_i - option['previous_oi'].to_i,
          volume_change: volume.to_i - option['previous_volume'].to_i,
          bid_ask_spread: (option['top_ask_price'].to_f - option['top_bid_price'].to_f).abs
        }
      end

      def min_delta_now
        h = Time.zone.now.hour
        return 0.45 if h >= 14
        return 0.35 if h >= 13
        return 0.30 if h >= 11

        0.25
      end

      def min_delta_for(strike_price, atm_strike)
        base =
          if Time.zone.now.hour >= 14
            0.45
          elsif Time.zone.now.hour >= 13
            0.35
          elsif Time.zone.now.hour >= 11
            0.30
          else
            0.25
          end

        steps_away = ((strike_price - atm_strike).abs / @strike_step.to_f).round
        # Relax by 0.05 per step away (cap at a sensible floor 0.20)
        [base - (0.05 * steps_away), 0.20].max
      end

      def atm_range_pct
        case iv_rank
        when 0.0..0.2 then 0.01
        when 0.2..0.5 then 0.015
        else 0.025
        end
      end

      def within_atm_range?(strike)
        pct = atm_range_pct
        strike.between?(@underlying_spot * (1 - pct), @underlying_spot * (1 + pct))
      end

      def within_enhanced_atm_range?(strike, signal_type)
        atm_strike = determine_atm_strike
        return false unless atm_strike

        base_range = atm_range_pct * @underlying_spot

        if signal_type == :ce
          strike >= atm_strike && strike <= (atm_strike + base_range)
        elsif signal_type == :pe
          strike <= atm_strike && strike >= (atm_strike - base_range)
        else
          within_atm_range?(strike)
        end
      end

      def itm_strike?(strike_price, signal_type)
        atm_strike = determine_atm_strike
        return false unless atm_strike

        case signal_type
        when :ce then strike_price < atm_strike
        when :pe then strike_price > atm_strike
        else false
        end
      end

      def deep_itm_strike?(strike_price, signal_type)
        atm_strike = determine_atm_strike
        return false unless atm_strike

        if signal_type == :ce
          strike_price < atm_strike * 0.8
        elsif signal_type == :pe
          strike_price > atm_strike * 1.2
        end
      end

      def deep_otm_strike?(strike_price, signal_type)
        atm_strike = determine_atm_strike
        return false unless atm_strike

        if signal_type == :ce
          strike_price > atm_strike * 1.2
        elsif signal_type == :pe
          strike_price < atm_strike * 0.8
        end
      end

      def option_active?(option)
        return false unless option.is_a?(Hash)

        numeric_keys = %w[last_price implied_volatility oi volume previous_close_price previous_volume previous_oi]
        has_numeric_values = numeric_keys.any? { |key| option[key].to_f.nonzero? }

        greek_keys = %w[delta gamma theta vega]
        has_greek_values = greek_keys.any? { |key| option.dig('greeks', key).to_f.nonzero? }

        has_numeric_values || has_greek_values
      end

      def debug_filter_reason(strike_price, option, signal_type, atm_strike)
        reasons = []
        reasons << 'iv=0'    if option['implied_volatility'].to_f.zero?
        reasons << 'price=0' if option['last_price'].to_f.zero?

        delta = option.dig('greeks', 'delta').to_f.abs
        min_d = min_delta_for(strike_price, atm_strike)
        reasons << "delta<#{min_d.round(2)}(#{delta.round(2)})" if delta < min_d

        reasons << 'deep_ITM' if deep_itm_strike?(strike_price, signal_type)
        reasons << 'deep_OTM' if deep_otm_strike?(strike_price, signal_type)
        reasons << 'outside_enhanced_ATM' unless within_enhanced_atm_range?(strike_price, signal_type)

        reasons
      end

      def get_strike_selection_guidance(signal_type)
        atm_strike = determine_atm_strike
        return {} unless atm_strike

        current_spot = @underlying_spot

        recs =
          if signal_type == :ce
            [atm_strike, snap_to_grid(atm_strike + @strike_step), snap_to_grid(atm_strike + (2 * @strike_step))]
          elsif signal_type == :pe
            [atm_strike, snap_to_grid(atm_strike - @strike_step), snap_to_grid(atm_strike - (2 * @strike_step))]
          else
            [atm_strike]
          end

        recs = recs.compact.uniq.select { |s| oc_strikes.include?(s) }

        {
          current_spot: current_spot,
          atm_strike: atm_strike,
          strike_step: @strike_step,
          recommended_strikes: recs,
          explanation: if signal_type == :ce
                         'CE strikes should be ATM or slightly OTM (never ITM)'
                       else
                         'PE strikes should be ATM or slightly OTM (never ITM)'
                       end
        }
      end

      def get_strike_filter_summary(signal_type)
        side = signal_type.to_sym
        atm_strike = determine_atm_strike
        strike_filters = {
          total_strikes: @option_chain[:oc].keys.size,
          filtered_count: 0,
          atm_strike: atm_strike,
          filters_applied: []
        }

        return strike_filters unless atm_strike

        filtered_strikes = gather_filtered_strikes(signal_type)
        strike_filters[:filtered_count] = filtered_strikes.size

        if filtered_strikes.empty?
          strike_filters[:filters_applied] << 'No strikes passed all filters'
          summary_window = summary_distance_threshold(atm_strike)

          @option_chain[:oc].each do |strike_str, data|
            option = data[side]
            next unless option
            next unless option_active?(option)

            strike_price = strike_str.to_f
            next if deep_itm_strike?(strike_price, signal_type) || deep_otm_strike?(strike_price, signal_type)

            distance_from_atm = (strike_price - atm_strike).abs
            next if distance_from_atm > summary_window

            reasons = []
            iv = option['implied_volatility'].to_f
            price = option['last_price'].to_f
            delta = option.dig('greeks', 'delta').to_f.abs
            min_delta = min_delta_for(strike_price, atm_strike)

            reasons << 'IV zero' if iv.zero?
            reasons << 'Price zero' if price.zero?
            reasons << "Delta low (< #{min_delta.round(2)})" if delta < min_delta
            reasons << 'Outside enhanced ATM range' unless within_enhanced_atm_range?(strike_price, signal_type)

            next unless reasons.any?

            strike_filters[:filters_applied] << {
              strike_price: strike_price,
              reasons: reasons,
              distance_from_atm: distance_from_atm,
              atm_range_multiple: summary_window.zero? ? 0 : distance_from_atm / summary_window,
              delta: delta,
              iv: iv,
              price: price
            }
          end
        else
          filtered_strikes.each do |opt|
            distance_from_atm = (opt[:strike_price] - atm_strike).abs
            atm_range = atm_range_pct * @underlying_spot

            strike_filters[:filters_applied] << {
              strike_price: opt[:strike_price],
              reasons: ['PASSED'],
              distance_from_atm: distance_from_atm,
              atm_range_multiple: distance_from_atm / atm_range,
              delta: opt[:greeks][:delta].abs,
              iv: opt[:iv],
              price: opt[:last_price]
            }
          end
        end

        strike_filters
      end
    end
  end
end
