# frozen_string_literal: true

module Option
  module Components
    class Scorer
      def initialize(ctx) = @ctx = ctx

      def score_for(opt, strategy, signal_type, signal_strength)
        spread     = opt[:bid_ask_spread] <= 0 ? 0.1 : opt[:bid_ask_spread]
        last_price = opt[:last_price].to_f
        relative_spread = spread / last_price

        oi         = [opt[:oi], 1].max
        volume     = [opt[:volume], 1].max
        delta      = opt[:greeks][:delta].abs
        gamma      = opt[:greeks][:gamma]
        theta      = opt[:greeks][:theta]
        vega       = opt[:greeks][:vega]
        price_chg  = opt[:price_change]
        oi_chg     = opt[:oi_change]
        vol_chg    = opt[:volume_change]

        lw, mw, = strategy == 'intraday' ? [0.35, 0.35, 0.3] : [0.25, 0.25, 0.5]

        liquidity_score = ((oi * volume) + vol_chg.abs) / (relative_spread.nonzero? || 0.01)

        momentum_score = (oi_chg / 1000.0)
        momentum_score += price_chg.positive? ? price_chg : price_chg.abs if delta >= 0 && price_chg.positive?

        days_left = (@ctx.expiry - Time.zone.today).to_i
        theta_penalty = theta.abs * (days_left < 3 ? 2.0 : 1.0)
        greeks_score = (delta * 100) + (gamma * 10) + (vega * 2) - (theta_penalty * 3)

        efficiency = price_chg.zero? ? 0.0 : price_chg / last_price
        efficiency_score = efficiency * 30

        atm = @ctx.atm_strike
        atm_pref = 0
        if atm
          dist = (opt[:strike_price] - atm).abs
          atm_range = @ctx.atm_range_pct * @ctx.spot
          atm_pref = if dist <= (atm_range * 0.1) then 100
                     elsif dist <= (atm_range * 0.3) then 80
                     elsif dist <= (atm_range * 0.6) then 50
                     elsif dist <= (atm_range * 1.0) then 20
                     else
                       0 end

          # ITM penalty
          atm_pref *= 0.7 if itm?(opt[:strike_price], signal_type, atm)
        end

        total = (liquidity_score * lw) +
                (momentum_score * mw) +
                (greeks_score * theta_weight) +
                efficiency_score +
                atm_pref

        z = local_iv_zscore(opt[:iv], opt[:strike_price])
        total *= 0.90 if z > 1.5

        tilt = skew_tilt
        total *= 1.10 if (signal_type == :ce && tilt == :call) || (signal_type == :pe && tilt == :put)

        if (hv = historical_volatility).positive?
          iv_ratio = opt[:iv] / hv
          total *= 0.9 if iv_ratio > 1.5
        end

        total * signal_strength
      end

      private

      def theta_weight
        Time.zone.now.hour >= 13 ? 4.0 : 3.0
      end

      def itm?(strike, side, atm)
        (side == :ce && strike < atm) || (side == :pe && strike > atm)
      end

      def local_iv_zscore(strike_iv, strike)
        neighbours = @ctx.oc_strikes.select { |s| (s - strike).abs <= 300 } # 3 steps of 100
        ivs = neighbours.map do |s|
          @ctx.oc[:oc][format('%.6f', s)]['ce']['implied_volatility'].to_f
        rescue StandardError
          nil
        end.compact
        return 0 if ivs.empty?

        mean = ivs.sum / ivs.size
        std  = Math.sqrt(ivs.sum { |v| (v - mean)**2 } / ivs.size)
        std.zero? ? 0 : (strike_iv - mean) / std
      end

      def skew_tilt
        ce_ivs = side_ivs('ce')
        pe_ivs = side_ivs('pe')
        avg_ce = ce_ivs.sum / ce_ivs.size.to_f if ce_ivs.any?
        avg_pe = pe_ivs.sum / pe_ivs.size.to_f if pe_ivs.any?
        return :call if avg_ce && avg_pe && avg_ce > avg_pe * 1.1
        return :put  if avg_pe && avg_ce && avg_pe > avg_ce * 1.1

        :neutral
      end

      def side_ivs(side_key)
        @ctx.oc[:oc].values.map do |row|
          iv = row.dig(side_key, 'implied_volatility')
          iv&.to_f if iv && iv.to_f > 0
        end.compact
      end

      def historical_volatility
        return 0 if @ctx.hist.blank?

        closes = @ctx.hist['close']
        returns = closes.each_cons(2).map do |a, b|
          Math.log(b / a)
        rescue StandardError
          0
        end
        mean = returns.sum / returns.size.to_f
        std  = Math.sqrt(returns.sum { |r| (r - mean)**2 } / returns.size.to_f)
        std * Math.sqrt(252) * 100
      end
    end
  end
end
