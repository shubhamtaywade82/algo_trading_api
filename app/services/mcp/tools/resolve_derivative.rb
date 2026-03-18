# frozen_string_literal: true

module Mcp
  module Tools
    # Tool that deterministically maps an option contract request
    # to the exact Dhan tradable instrument identifiers.
    #
    # This is a read-only resolver: it must not place orders.
    class ResolveDerivative
      def self.name
        'resolve_derivative'
      end

      def self.definition
        {
          name: name,
          title: 'Resolve derivative instrument',
          description: 'Maps symbol + expiry + strike + option_type to a Dhan tradable option instrument',
          inputSchema: {
            type: 'object',
            properties: {
              symbol: { type: 'string', description: 'Underlying index symbol: NIFTY | BANKNIFTY | SENSEX' },
              expiry: { type: 'string', description: 'Expiry date (YYYY-MM-DD)' },
              strike: { type: 'integer', description: 'Option strike price' },
              strike_price: { type: 'integer', description: 'Alias for strike' },
              option_type: { type: 'string', description: 'CE | PE', enum: %w[CE PE] },
              min_oi: { type: 'integer', description: 'Minimum open interest guard' },
              min_volume: { type: 'integer', description: 'Minimum volume guard' }
            },
            required: %w[symbol expiry option_type]
          }
        }
      end

      def self.execute(args)
        opts = args.with_indifferent_access

        symbol = normalize_symbol(opts[:symbol])
        expiry_date = parse_expiry_date(opts[:expiry])
        strike = normalize_strike(opts[:strike] || opts[:strike_price])
        option_type = normalize_option_type(opts[:option_type])
        min_oi = normalize_min(opts[:min_oi], default_min_oi)
        min_volume = normalize_min(opts[:min_volume], default_min_volume)

        derivative = find_derivative!(
          underlying_symbol: symbol,
          expiry_date: expiry_date,
          strike_price: strike,
          option_type: option_type
        )

        instrument = resolve_underlying_instrument!(derivative, symbol)
        option_chain = instrument.fetch_option_chain(expiry_date)
        raise 'Option chain unavailable' if option_chain.blank?

        validate_option_chain_leg!(
          option_chain: option_chain,
          strike: strike,
          option_type: option_type,
          min_oi: min_oi,
          min_volume: min_volume
        )

        build_response(derivative)
      rescue StandardError => e
        { error: e.message }
      end

      class << self
        private

        def normalize_symbol(value)
          symbol = value.to_s.upcase.strip.presence
          raise 'Symbol required' if symbol.blank?

          validate_symbol!(symbol)
          symbol
        end

        def validate_symbol!(symbol)
          return if %w[NIFTY BANKNIFTY SENSEX].include?(symbol)

          raise "Unsupported symbol: #{symbol}"
        end

        def parse_expiry_date(value)
          return value.iso8601 if value.respond_to?(:iso8601)

          Date.iso8601(value.to_s)
        rescue ArgumentError
          raise 'Invalid expiry date; expected YYYY-MM-DD'
        end

        def normalize_strike(value)
          strike = value.to_i
          raise 'Strike must be > 0' if strike <= 0
          strike
        end

        def normalize_option_type(value)
          option_type = value.to_s.upcase.strip
          raise 'Invalid option_type' unless %w[CE PE].include?(option_type)

          option_type
        end

        def normalize_min(value, default_value)
          return default_value if value.blank?

          int_value = value.to_i
          raise 'min_oi/min_volume must be >= 0' if int_value.negative?

          int_value
        end

        def default_min_oi
          Integer(ENV.fetch('DERIVATIVE_RESOLVER_MIN_OI', 1_000))
        end

        def default_min_volume
          Integer(ENV.fetch('DERIVATIVE_RESOLVER_MIN_VOLUME', 500))
        end

        def find_derivative!(underlying_symbol:, expiry_date:, strike_price:, option_type:)
          Derivative.find_by(
            underlying_symbol: underlying_symbol,
            expiry_date: expiry_date,
            strike_price: strike_price,
            option_type: option_type
          ) || raise("Derivative contract not found for #{underlying_symbol} #{expiry_date} #{strike_price} #{option_type}")
        end

        def resolve_underlying_instrument!(derivative, symbol)
          return Instrument.find_by!(security_id: derivative.underlying_security_id.to_s) if derivative.underlying_security_id.present?

          Instrument.segment_index.find_by!(underlying_symbol: symbol, exchange: exchange_for_symbol(symbol))
        end

        def exchange_for_symbol(symbol)
          return 'bse' if symbol == 'SENSEX'

          'nse'
        end

        def validate_option_chain_leg!(option_chain:, strike:, option_type:, min_oi:, min_volume:)
          oc = option_chain[:oc] || option_chain['oc']
          raise 'Option chain missing oc payload' if oc.blank?

          oc_indifferent = oc.with_indifferent_access
          option_data = oc_indifferent[strike.to_s] || oc_indifferent[strike]
          raise 'Strike not present in option chain' if option_data.blank?

          option_data_indifferent = option_data.with_indifferent_access

          leg_key = option_type == 'CE' ? :ce : :pe
          leg = option_data_indifferent[leg_key]
          raise "Option chain leg missing for #{option_type}" if leg.blank?

          leg_indifferent = leg.with_indifferent_access

          oi = extract_number(leg_indifferent, :oi, :openInterest, :open_interest)
          volume = extract_number(leg_indifferent, :volume, :vol)

          raise 'Option chain missing OI' if oi.nil?
          raise 'Option chain missing volume' if volume.nil?

          raise "Illiquid strike (low OI: #{oi})" if oi < min_oi
          raise "Illiquid strike (low volume: #{volume})" if volume < min_volume
        end

        def extract_number(hash, *keys)
          keys.each do |key|
            return hash[key].to_i if hash[key].present?
          end
          nil
        end

        def build_response(derivative)
          trading_symbol = derivative.symbol_name.presence || derivative.display_name.presence || derivative.underlying_symbol
          {
            security_id: derivative.security_id.to_s,
            exchange_segment: derivative.exchange_segment,
            trading_symbol: trading_symbol,
            lot_size: derivative.lot_size.to_i,
            expiry: derivative.expiry_date.iso8601,
            strike: derivative.strike_price.to_i,
            option_type: derivative.option_type
          }
        end
      end
    end
  end
end

