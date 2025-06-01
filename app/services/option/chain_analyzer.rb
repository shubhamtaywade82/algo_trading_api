# frozen_string_literal: true

module Option
  class ChainAnalyzer
    IV_RANK_MIN     = 0.00
    IV_RANK_MAX     = 0.80
    # MIN_DELTA       = 0.30
    ATM_RANGE_PCT   = 0.01 # 1%
    THETA_AVOID_HOUR = 14.5 # 2:30 PM as float

    TOP_RANKED_LIMIT = 5

    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data, :iv_rank

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [])
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = Date.parse(expiry.to_s)
      @underlying_spot  = underlying_spot.to_f
      @iv_rank          = iv_rank.to_f
      @historical_data  = historical_data || []

      Rails.logger.debug { "Analysing Options for #{expiry}" }
      raise ArgumentError, 'Option Chain is missing or empty!' if @option_chain[:oc].blank?
    end

    def analyze(signal_type:, strategy_type:)
      return { proceed: false, reason: 'IV rank outside range' } if iv_rank_outside_range?
      return { proceed: false, reason: 'Late entry, theta risk' } if discourage_late_entry_due_to_theta?

      trend = intraday_trend
      return { proceed: false, reason: 'Trend does not confirm signal' } unless trend_confirms?(trend, signal_type)

      filtered = gather_filtered_strikes(signal_type)
      return { proceed: false, reason: 'No tradable strikes found' } if filtered.empty?

      ranked = filtered.map do |opt|
        opt.merge(score: score_for(opt, strategy_type))
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

        # ⛔ Skip strikes with no valid IV or price
        next if option['implied_volatility'].to_f.zero? || option['last_price'].to_f.zero?

        # TODO: Skip illiquid strikes where you can’t even buy 3 lots at the ask
        # next if option['top_ask_quantity'].to_i < (3 * lot_size(option_key))

        strike_price = strike_str.to_f
        delta = option.dig('greeks', 'delta').to_f.abs

        # ⛔ Skip strikes with delta below minimum threshold
        next if delta < min_delta_now

        # ⛔ Skip if strike is outside ATM range
        next unless within_atm_range?(strike_price)

        build_strike_data(strike_price, option, data['volume'])
      end
    end

    def min_delta_now
      h = Time.zone.now.hour
      return 0.45 if h >= 14
      return 0.35 if h >= 13
      return 0.30 if h >= 11

      0.25
    end

    def within_atm_range?(strike)
      strike.between?(@underlying_spot * (1 - ATM_RANGE_PCT), @underlying_spot * (1 + ATM_RANGE_PCT))
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

    def score_for(opt, strategy)
      spread     = opt[:bid_ask_spread] <= 0 ? 0.1 : opt[:bid_ask_spread]
      oi         = [opt[:oi], 1].max
      volume     = [opt[:volume], 1].max
      delta      = opt[:greeks][:delta].abs
      gamma      = opt[:greeks][:gamma]
      theta      = opt[:greeks][:theta]
      vega       = opt[:greeks][:vega]
      price_chg  = opt[:price_change]
      oi_chg     = opt[:oi_change]
      vol_chg    = opt[:volume_change]

      lw, mw, gw = strategy == 'intraday' ? [0.35, 0.35, 0.3] : [0.25, 0.25, 0.5]

      liquidity_score = ((oi * volume) + vol_chg.abs) / spread
      momentum_score = (oi_chg / 1000.0)
      momentum_score += price_chg.positive? ? price_chg : price_chg.abs if delta >= 0 && price_chg.positive?
      greeks_score = (delta * 100) + (gamma * 10) + (vega * 2) - (theta.abs * 3)

      total = (liquidity_score * lw) + (momentum_score * mw) + (greeks_score * theta_weight)
      # total *= 0.9 if opt[:iv] > 40 && strategy != 'intraday'
      z = local_iv_zscore(opt[:iv], opt[:strike_price])
      total *= 0.90 if z > 1.5
      total
    end

    def theta_weight
      Time.zone.now.hour >= 13 ? 4.0 : 3.0
    end

    # Down-rank strikes whose IV is far above the local smile (they’re expensive).
    # Z-score vs linear fit of ±3 strikes; if z > 1.5 shave 10 % off total score.
    def local_iv_zscore(strike_iv, strike)
      neighbours = @option_chain[:oc].keys.map(&:to_f)
                                     .select { |s| (s - strike).abs <= 3 * 100 } # 3 strikes ≈ 300-₹ span
      ivs = neighbours.map { |s| @option_chain[:oc][format('%.6f', s)]['ce']['implied_volatility'].to_f }
      mean = ivs.sum / ivs.size
      std = Math.sqrt(ivs.map { |v| (v - (ivs.sum / ivs.size))**2 }.sum / ivs.size)
      std.zero? ? 0 : (strike_iv - mean) / std
    end

    def intraday_trend
      atm_strike = determine_atm_strike
      atm_key = format('%.6f', atm_strike)
      ce = @option_chain[:oc].dig(atm_key, 'ce')
      pe = @option_chain[:oc].dig(atm_key, 'pe')
      return :neutral unless ce && pe

      ce_change = ce['last_price'].to_f - ce['previous_close_price'].to_f
      pe_change = pe['last_price'].to_f - pe['previous_close_price'].to_f

      return :bullish if ce_change.positive? && pe_change.negative?
      return :bearish if ce_change.negative? && pe_change.positive?

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
