# frozen_string_literal: true

module Option
  class ChainAnalyzer
    IV_RANK_MIN     = 0.00
    IV_RANK_MAX     = 0.80
    MIN_DELTA       = 0.30
    ATM_RANGE_PCT   = 0.01 # 1%
    THETA_AVOID_HOUR = 14.5 # 2:30 PM as float

    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data, :iv_rank

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [])
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = Date.parse(expiry.to_s)
      @underlying_spot  = underlying_spot.to_f
      @iv_rank          = iv_rank.to_f
      @historical_data  = historical_data || []

      raise ArgumentError, 'Option Chain is missing or empty!' if @option_chain[:oc].blank?
    end

    def analyze(signal_type:, strategy_type:)
      return [] if iv_rank_outside_range?

      all_filtered = gather_filtered_strikes(signal_type)

      return [] if all_filtered.empty?

      ranked = all_filtered.map do |opt|
        opt.merge(score: score_for(opt, strategy_type))
      end.sort_by { |o| -o[:score] }

      top_candidates = ranked.first(3)

      if need_historical_fallback?(top_candidates)
        trend = intraday_trend
        return [] unless trend_confirms?(trend, signal_type)
      end

      if discourage_late_entry_due_to_theta?
        Rails.logger.info 'Theta decay risk detected (post 2:30 PM on expiry), skipping trade'
        return []
      end

      top_candidates
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

        strike_price = strike_str.to_f
        delta = option.dig('greeks', 'delta').to_f.abs
        next if delta < MIN_DELTA
        next unless within_atm_range?(strike_price)

        build_strike_data(strike_price, option, data['volume'])
      end
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

      # Weights based on strategy
      lw, mw, gw = strategy == 'intraday' ? [0.35, 0.35, 0.3] : [0.25, 0.25, 0.5]

      liquidity_score = ((oi * volume) + vol_chg.abs) / spread
      momentum_score = (oi_chg / 1000.0)
      momentum_score += price_chg.positive? ? price_chg : price_chg.abs if delta >= 0 && price_chg.positive?
      greeks_score = (delta * 100) + (gamma * 10) + (vega * 2) - (theta.abs * 3)

      total = (liquidity_score * lw) + (momentum_score * mw) + (greeks_score * gw)
      total *= 0.9 if opt[:iv] > 40 && strategy != 'intraday'
      total
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

    def need_historical_fallback?(ranked)
      top = ranked.first
      return true if top[:score] < 5.0
      return true if ranked.size > 1 && (ranked[0][:score] - ranked[1][:score]).abs < 0.2

      false
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

    def summarize_greeks
      greeks = %w[delta gamma theta vega].index_with { [] }

      @option_chain[:oc].each_value do |row|
        %w[ce pe].each do |side|
          next unless row[side]

          g = row[side]['greeks'] || {}
          greeks.each_key { |k| greeks[k] << g[k].to_f if g[k] }
        end
      end

      greeks.transform_values { |vals| average(vals) }
    end

    def analyze_volatility
      ivs = []
      @option_chain[:oc].each_value do |row|
        ivs << row.dig(:ce, 'implied_volatility').to_f if row[:ce]
        ivs << row.dig(:pe, 'implied_volatility').to_f if row[:pe]
      end
      avg = average(ivs)
      { average_iv: avg, high_volatility: avg > 20 }
    end

    def average(array)
      return 0.0 if array.empty?

      array.sum / array.size
    end
  end
end
