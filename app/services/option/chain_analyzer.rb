# frozen_string_literal: true

module Option
  class ChainAnalyzer
    IV_RANK_MIN       = 0.00
    IV_RANK_MAX       = 0.80
    BASE_ATM_RANGE_PCT = 0.01 # fallback minimum range
    THETA_AVOID_HOUR = 14.5 # 2:30 PM as float

    TOP_RANKED_LIMIT = 5

    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data, :iv_rank

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [])
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = Date.parse(expiry.to_s)
      @underlying_spot  = underlying_spot.to_f
      @iv_rank          = iv_rank.to_f
      @historical_data  = historical_data || []

      Rails.logger.debug { "Analyzing Options for #{expiry}" }
      raise ArgumentError, 'Option Chain is missing or empty!' if @option_chain[:oc].blank?
    end

    def analyze(signal_type:, strategy_type:, signal_strength: 1.0)
      return { proceed: false, reason: 'IV rank outside range' } if iv_rank_outside_range?
      return { proceed: false, reason: 'Late entry, theta risk' } if discourage_late_entry_due_to_theta?

      trend = intraday_trend
      return { proceed: false, reason: 'Trend does not confirm signal' } unless trend_confirms?(trend, signal_type)

      filtered = gather_filtered_strikes(signal_type)
      return { proceed: false, reason: 'No tradable strikes found' } if filtered.empty?

      ranked = filtered.map do |opt|
        score = score_for(opt, strategy_type, signal_type, signal_strength)
        opt.merge(score: score)
      end.sort_by { |o| -o[:score] }

      top_candidates = ranked.first(TOP_RANKED_LIMIT)

      {
        proceed: true,
        trend: trend,
        signal_type: signal_type,
        selected: top_candidates.first,
        ranked: top_candidates
      }
    end

    private

    def iv_rank_outside_range?
      @iv_rank < IV_RANK_MIN || @iv_rank > IV_RANK_MAX
    end

    def gather_filtered_strikes(signal_type)
      side = signal_type.to_sym

      @option_chain[:oc].filter_map do |strike_str, data|
        option = data[side]
        next unless option

        # Skip strikes with no valid IV or price
        next if option['implied_volatility'].to_f.zero? || option['last_price'].to_f.zero?

        strike_price = strike_str.to_f
        delta = option.dig('greeks', 'delta').to_f.abs

        # Skip strikes with low delta
        next if delta < min_delta_now

        # Skip strikes outside adaptive ATM range
        next unless within_atm_range?(strike_price)

        build_strike_data(strike_price, option, data['volume'])
      end
    end

    # Dynamic minimum delta thresholds depending on time of day
    def min_delta_now
      h = Time.zone.now.hour
      return 0.45 if h >= 14
      return 0.35 if h >= 13
      return 0.30 if h >= 11

      0.25
    end

    # Dynamic ATM range based on volatility
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

      # Liquidity score normalized for spread
      liquidity_score = ((oi * volume) + vol_chg.abs) / (relative_spread.nonzero? || 0.01)

      # Momentum
      momentum_score = (oi_chg / 1000.0)
      momentum_score += price_chg.positive? ? price_chg : price_chg.abs if delta >= 0 && price_chg.positive?

      # Time-to-expiry penalty on theta
      days_left = (@expiry - Date.today).to_i
      theta_penalty = theta.abs * (days_left < 3 ? 2.0 : 1.0)
      greeks_score = (delta * 100) + (gamma * 10) + (vega * 2) - (theta_penalty * 3)

      # Add price-to-premium efficiency
      efficiency = price_chg.zero? ? 0.0 : price_chg / last_price
      efficiency_score = efficiency * 30 # weight tuning factor

      total = (liquidity_score * lw) +
              (momentum_score * mw) +
              (greeks_score * theta_weight) +
              efficiency_score

      # Adjust for local IV skew
      z = local_iv_zscore(opt[:iv], opt[:strike_price])
      total *= 0.90 if z > 1.5

      # Check skew tilt
      tilt = skew_tilt
      if signal_type == :ce && tilt == :call
        total *= 1.10
      elsif signal_type == :pe && tilt == :put
        total *= 1.10
      end

      # Historical IV sanity check
      hist_vol = historical_volatility
      if hist_vol.positive?
        iv_ratio = opt[:iv] / hist_vol
        total *= 0.9 if iv_ratio > 1.5
      end

      # Factor in external signal strength
      total *= signal_strength

      total
    end

    def theta_weight
      Time.zone.now.hour >= 13 ? 4.0 : 3.0
    end

    def local_iv_zscore(strike_iv, strike)
      neighbours = @option_chain[:oc].keys.map(&:to_f)
                                     .select { |s| (s - strike).abs <= 3 * 100 }
      ivs = neighbours.map do |s|
        @option_chain[:oc][format('%.6f', s)]['ce']['implied_volatility'].to_f
      end
      return 0 if ivs.empty?

      mean = ivs.sum / ivs.size
      std = Math.sqrt(ivs.sum { |v| (v - mean)**2 } / ivs.size)
      std.zero? ? 0 : (strike_iv - mean) / std
    end

    def skew_tilt
      ce_ivs = collect_side_ivs(:ce)
      pe_ivs = collect_side_ivs(:pe)

      avg_ce = ce_ivs.sum / ce_ivs.size.to_f if ce_ivs.any?
      avg_pe = pe_ivs.sum / pe_ivs.size.to_f if pe_ivs.any?

      return :call if avg_ce && avg_pe && avg_ce > avg_pe * 1.1
      return :put if avg_pe && avg_ce && avg_pe > avg_ce * 1.1

      :neutral
    end

    def collect_side_ivs(side)
      @option_chain[:oc].values.map do |data|
        iv = data.dig(side.to_s, 'implied_volatility')
        iv&.to_f if iv && iv.to_f > 0
      end.compact
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

    def trend_confirms?(trend, signal_type)
      return true if trend == :neutral

      (trend == :bullish && signal_type == :ce) || (trend == :bearish && signal_type == :pe)
    end

    def discourage_late_entry_due_to_theta?
      now = Time.zone.now
      expiry_today = @expiry == now.to_date
      current_hour = now.hour + (now.min / 60.0)
      expiry_today && current_hour > THETA_AVOID_HOUR
    end

    def determine_atm_strike
      strikes = @option_chain[:oc].keys.map(&:to_f)
      return nil if strikes.empty?

      strikes.min_by { |s| (s - @underlying_spot).abs }
    end
  end
end
