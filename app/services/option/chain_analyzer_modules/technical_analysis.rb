# frozen_string_literal: true

module Option
  module ChainAnalyzerModules
    # Technical analysis methods for ChainAnalyzer
    module TechnicalAnalysis
      def build_ta_snapshot
        return nil if @historical_data.blank?

        closes = Array(@historical_data['close']).compact
        if closes.size < Indicators::HolyGrail::EMA_SLOW
          Rails.logger.debug do
            "[ChainAnalyzer] Skipping HolyGrail TA – need ≥ #{Indicators::HolyGrail::EMA_SLOW} candles, got #{closes.size}"
          end
          return nil
        end

        Indicators::HolyGrail.call(candles: @historical_data)
      rescue ArgumentError => e
        Rails.logger.debug { "[ChainAnalyzer] HolyGrail TA unavailable – #{e.message}" }
        nil
      rescue StandardError => e
        Rails.logger.warn { "[ChainAnalyzer] HolyGrail TA failed – #{e.message}" }
        nil
      end

      def intraday_trend
        window = 3
        sums = { ce: 0.0, pe: 0.0 }

        strikes = @option_chain[:oc].keys.map(&:to_f)
        atm = determine_atm_strike
        strikes.select { |s| (s - atm).abs <= window * 100 }.each do |s|
          key = format('%.6f', s)
          %i[ce pe].each do |side|
            opt = @option_chain[:oc].dig(key, side.to_s)
            next unless opt

            change = opt['last_price'].to_f - opt['previous_close_price'].to_f
            sums[side] += change
          end
        end

        diff = sums[:ce] - sums[:pe]
        return :bullish if diff.positive?
        return :bearish if diff.negative?

        :neutral
      end

      def historical_volatility
        return 0 if @historical_data.empty?

        closes = @historical_data['close']
        returns = closes.each_cons(2).map do |a, b|
          Math.log(b / a)
        rescue StandardError
          0
        end
        std_dev = Math.sqrt(returns.sum { |r| (r - (returns.sum / returns.size))**2 } / returns.size)
        std_dev * Math.sqrt(252) * 100 # Annualized historical volatility as percentage
      end
    end
  end
end
