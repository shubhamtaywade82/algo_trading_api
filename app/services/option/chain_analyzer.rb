# frozen_string_literal: true

module Option
  class ChainAnalyzer
    IV_RANK_MIN       = 0.00
    IV_RANK_MAX       = 0.80
    BASE_ATM_RANGE_PCT = 0.01 # fallback minimum range
    THETA_AVOID_HOUR = 14.5 # 2:30 PM as float
    MIN_ADX_VALUE = Rails.env.production? ? 20 : 10

    TOP_RANKED_LIMIT = 10

    attr_reader :option_chain, :expiry, :underlying_spot, :historical_data, :iv_rank, :ta

    def initialize(option_chain, expiry:, underlying_spot:, iv_rank:, historical_data: [], strike_step: nil)
      @option_chain     = option_chain.with_indifferent_access
      @expiry           = Date.parse(expiry.to_s)
      @underlying_spot  = underlying_spot.to_f
      @iv_rank          = iv_rank.to_f
      @historical_data  = historical_data || []
      @ta = Indicators::HolyGrail.call(candles: historical_data) if historical_data.present?

      @strike_step = strike_step || infer_strike_step
      Rails.logger.debug { "Analyzing Options for #{expiry}" }
      raise ArgumentError, 'Option Chain is missing or empty!' if @option_chain[:oc].blank?
    end

    def analyze(signal_type:, strategy_type:, signal_strength: 1.0)
      # ------------------------------------------------------------------
      # initialise skeleton result
      # ------------------------------------------------------------------
      result = {
        proceed: true, # optimistic default
        reason: nil,
        reasons: [], # Multiple reasons for comprehensive feedback
        signal_type: signal_type,
        trend: nil,
        momentum: nil,
        adx: nil,
        selected: nil,
        ranked: [],
        ta_snapshot: ta ? ta.to_h : {},
        validation_details: {} # Detailed validation information
      }

      # ------------------------------------------------------------------
      # 0️⃣  Tech-analysis veto (uncomment if you want a hard block)
      # ------------------------------------------------------------------
      # if ta&.proceed? == false
      #   result.merge!(proceed: false, reason: 'holy_grail_veto')
      #   return result
      # end

      # ------------------------------------------------------------------
      # 1️⃣  Sanity checks that are always required
      # ------------------------------------------------------------------
      validation_checks = perform_validation_checks(signal_type, strategy_type)

      if validation_checks[:failed].any?
        result[:proceed] = false
        result[:reasons] = validation_checks[:failed]
        result[:reason] = validation_checks[:failed].join('; ') # Backward compatibility
        result[:validation_details] = validation_checks[:details]
        return result
      end

      # ------------------------------------------------------------------
      # 2️⃣  Spot bias, momentum & ADX from HolyGrail (or legacy fallback)
      # ------------------------------------------------------------------
      result[:trend]    = ta ? ta.bias.to_sym      : intraday_trend
      result[:momentum] = ta ? ta.momentum.to_sym  : :flat
      result[:adx]      = ta&.adx
      adx_ok            = ta ? ta.adx.to_f >= MIN_ADX_VALUE : true

      # Check trend confirmation and momentum
      trend_momentum_check = check_trend_momentum(result[:trend], result[:momentum], adx_ok, signal_type)
      unless trend_momentum_check[:passed]
        result[:proceed] = false
        result[:reasons] = trend_momentum_check[:reasons]
        result[:reason] = trend_momentum_check[:reasons].join('; ')
        result[:validation_details][:trend_momentum] = trend_momentum_check[:details]
        return result
      end

      # ------------------------------------------------------------------
      # 3️⃣  Strike selection & scoring  (only when all gates passed)
      # ------------------------------------------------------------------
      if result[:proceed]
        filtered = gather_filtered_strikes(signal_type)

        if filtered.empty?
          result[:proceed] = false
          result[:reasons] = ['No tradable strikes found']
          result[:reason] = 'No tradable strikes found'
          result[:validation_details][:strike_selection] = get_strike_filter_summary(signal_type)
        else
          m_boost = result[:momentum] == :strong ? 1.15 : 1.0
          ranked  = filtered.map do |opt|
                      score = score_for(opt, strategy_type,
                                        signal_type, signal_strength) * m_boost
                      opt.merge(score: score)
                    end.sort_by { |o| -o[:score] }

          result[:ranked]   = ranked.first(TOP_RANKED_LIMIT)
          result[:selected] = result[:ranked].first

          result[:validation_details][:strike_selection] = {
            total_strikes: @option_chain[:oc].keys.size,
            filtered_count: filtered.size,
            ranked_count: result[:ranked].size,
            top_score: result[:selected]&.dig(:score)&.round(2),
            filters_applied: get_strike_filter_summary(signal_type),
            strike_guidance: get_strike_selection_guidance(signal_type)
          }
        end
      end

      # ------------------------------------------------------------------
      # 4️⃣  final return  (single exit-point)
      # ------------------------------------------------------------------
      result
    end

    # ------------------------------------------------------------------
    # 🎯  Public helper – fetch the latest intraday trend
    #      (keeps the heavy-lifting method itself private)
    # ------------------------------------------------------------------
    # alias: `trend`
    def current_trend
      intraday_trend
    end
    alias trend current_trend

    private

    def oc_strikes
      @oc_strikes ||= @option_chain[:oc].keys.map(&:to_f).sort
    end

    # Try to infer the strike step from the chain; fallback to common index steps.
    def infer_strike_step
      diffs = oc_strikes.each_cons(2).map { |a, b| (b - a).abs }.reject(&:zero?)
      step  = diffs.group_by(&:round).max_by { |_k, v| v.size }&.first&.to_f
      return step if step&.positive?

      # Fallback heuristics (index defaults)
      # If you can pass instrument context, prefer that. For now, use 50 as safe default for NIFTY-like.
      50.0
    end

    def nearest_grid(strike)
      oc_strikes.min_by { |s| (s - strike).abs } # ensure we return an existing strike
      # (We could also snap to @strike_step multiples around ATM, then pick closest present in oc_strikes)
    end

    def snap_to_grid(strike)
      # Snap to nearest multiple of @strike_step around the ATM, then clamp to an existing strike in oc
      return nil if oc_strikes.empty?

      atm = determine_atm_strike
      return oc_strikes.first unless atm

      # compute offset multiples by step, then clamp to existing strikes
      delta  = strike - atm
      steps  = (delta / @strike_step.to_f).round
      target = atm + (steps * @strike_step.to_f)
      # pick closest existing strike to the target
      oc_strikes.min_by { |s| (s - target).abs }
    end

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

    # Enhanced ATM range logic to ensure only ATM, near ATM, or slightly OTM strikes
    def within_enhanced_atm_range?(strike, signal_type)
      atm_strike = determine_atm_strike
      return false unless atm_strike

      # Calculate distance from ATM strike
      distance_from_atm = (strike - atm_strike).abs

      # Define acceptable ranges based on signal type and market conditions
      base_range = atm_range_pct * @underlying_spot

      # For calls (CE): prefer strikes at or above ATM (slightly OTM is fine, but never ITM)
      if signal_type == :ce
        # Allow strikes from ATM up to slightly above ATM (slightly OTM)
        # Never allow strikes below ATM (which would be ITM)
        strike >= atm_strike && strike <= (atm_strike + base_range)
      # For puts (PE): prefer strikes at or below ATM (slightly OTM is fine, but never ITM)
      elsif signal_type == :pe
        # Allow strikes from ATM down to slightly below ATM (slightly OTM)
        # Never allow strikes above ATM (which would be ITM)
        strike <= atm_strike && strike >= (atm_strike - base_range)
      else
        # Fallback to original logic for unknown signal types
        within_atm_range?(strike)
      end
    end

    # Get optimal strike selection guidance for current market conditions
    def get_strike_selection_guidance(signal_type)
      atm_strike = determine_atm_strike
      return {} unless atm_strike

      current_spot = @underlying_spot

      recs =
        if signal_type == :ce
          # ATM and OTM upwards (never ITM)
          [atm_strike,
           snap_to_grid(atm_strike + @strike_step),
           snap_to_grid(atm_strike + (2 * @strike_step))]
        elsif signal_type == :pe
          # ATM and OTM downwards (never ITM)
          [atm_strike,
           snap_to_grid(atm_strike - @strike_step),
           snap_to_grid(atm_strike - (2 * @strike_step))]
        else
          [atm_strike]
        end

      recs = recs.compact.uniq.select { |s| oc_strikes.include?(s) }

      {
        current_spot: current_spot,
        atm_strike: atm_strike,
        strike_step: @strike_step, # 👈 expose for logs
        recommended_strikes: recs,
        explanation: if signal_type == :ce
                       'CE strikes should be ATM or slightly OTM (never ITM)'
                     else
                       'PE strikes should be ATM or slightly OTM (never ITM)'
                     end
      }
    end

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
      days_left = (@expiry - Time.zone.today).to_i
      theta_penalty = theta.abs * (days_left < 3 ? 2.0 : 1.0)
      greeks_score = (delta * 100) + (gamma * 10) + (vega * 2) - (theta_penalty * 3)

      # Add price-to-premium efficiency
      efficiency = price_chg.zero? ? 0.0 : price_chg / last_price
      efficiency_score = efficiency * 30 # weight tuning factor

      # ATM preference score - heavily favor strikes close to ATM
      atm_strike = determine_atm_strike
      atm_preference_score = 0
      if atm_strike
        distance_from_atm = (opt[:strike_price] - atm_strike).abs
        atm_range = atm_range_pct * @underlying_spot

        # Perfect ATM gets maximum score
        atm_preference_score = if distance_from_atm <= (atm_range * 0.1)
                                 100
                               # Near ATM gets high score
                               elsif distance_from_atm <= (atm_range * 0.3)
                                 80
                               # Slightly away from ATM gets medium score
                               elsif distance_from_atm <= (atm_range * 0.6)
                                 50
                               # Further from ATM gets low score
                               elsif distance_from_atm <= (atm_range * 1.0)
                                 20
                               else
                                 0
                               end

        # Additional penalty for ITM strikes
        if itm_strike?(opt[:strike_price], signal_type)
          atm_preference_score *= 0.7 # 30% penalty for ITM
        end
      end

      total = (liquidity_score * lw) +
              (momentum_score * mw) +
              (greeks_score * theta_weight) +
              efficiency_score +
              atm_preference_score

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
      @option_chain[:oc].values.filter_map do |data|
        iv = data.dig(side.to_s, 'implied_volatility')
        iv&.to_f if iv&.to_f&.positive?
      end
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
      return nil if oc_strikes.empty?

      spot = (@option_chain[:last_price] || @underlying_spot).to_f
      oc_strikes.min_by { |s| (s - spot).abs }
    end

    def itm_strike?(strike_price, signal_type)
      atm_strike = determine_atm_strike
      return false unless atm_strike

      case signal_type
      when :ce
        # For calls: strike < ATM is ITM
        strike_price < atm_strike
      when :pe
        # For puts: strike > ATM is ITM
        strike_price > atm_strike
      else
        false
      end
    end

    def deep_itm_strike?(strike_price, signal_type)
      atm_strike = determine_atm_strike
      return false unless atm_strike

      if signal_type == :ce
        strike_price > atm_strike * 1.2 # Deep ITM for calls
      elsif signal_type == :pe
        strike_price < atm_strike * 0.8 # Deep ITM for puts
      end
    end

    def deep_otm_strike?(strike_price, signal_type)
      atm_strike = determine_atm_strike
      return false unless atm_strike

      if signal_type == :ce
        strike_price < atm_strike * 0.8 # Deep OTM for calls
      elsif signal_type == :pe
        strike_price > atm_strike * 1.2 # Deep OTM for puts
      end
    end

    def perform_validation_checks(signal_type, strategy_type)
      checks = {
        failed: [],
        details: {}
      }

      # 1️⃣  IV Rank Check
      if iv_rank_outside_range?
        checks[:failed] << 'IV rank outside range'
        checks[:details][:iv_rank] = {
          current_rank: @iv_rank,
          min_rank: IV_RANK_MIN,
          max_rank: IV_RANK_MAX
        }
      end

      # 2️⃣  Theta Risk Check
      if discourage_late_entry_due_to_theta?
        checks[:failed] << 'Late entry, theta risk'
        checks[:details][:theta_risk] = {
          current_time: Time.zone.now.strftime('%H:%M'),
          expiry_date: @expiry.strftime('%Y-%m-%d'),
          hours_left: (@expiry - Time.zone.today).to_i,
          theta_avoid_hour: THETA_AVOID_HOUR
        }
      end

      # 3️⃣  ADX Check
      adx_ok = ta ? ta.adx.to_f >= MIN_ADX_VALUE : true
      unless adx_ok
        checks[:failed] << "ADX below minimum value (#{ta&.adx})"
        checks[:details][:adx] = {
          current_value: ta&.adx,
          min_value: MIN_ADX_VALUE
        }
      end

      # 4️⃣  Trend Confirmation Check
      trend = ta ? ta.bias.to_sym : intraday_trend
      momentum = ta ? ta.momentum.to_sym : :flat
      trend_momentum_check = check_trend_momentum(trend, momentum, adx_ok, signal_type)
      unless trend_momentum_check[:passed]
        checks[:failed] << trend_momentum_check[:reasons].join('; ')
        checks[:details][:trend_momentum] = trend_momentum_check[:details]
      end

      checks
    end

    def check_trend_momentum(trend, momentum, adx_ok, signal_type)
      reasons = []
      details = {}

      if trend == :neutral
        reasons << 'Trend is neutral'
        details[:trend] = {
          current_trend: trend,
          signal_type: signal_type
        }
      end

      if signal_type == :ce && trend == :bearish
        reasons << 'Call signal, but trend is bearish'
        details[:trend_mismatch] = {
          signal_type: signal_type,
          current_trend: trend
        }
      end

      if signal_type == :pe && trend == :bullish
        reasons << 'Put signal, but trend is bullish'
        details[:trend_mismatch] = {
          signal_type: signal_type,
          current_trend: trend
        }
      end

      if momentum == :flat
        reasons << 'Momentum is flat'
        details[:momentum] = {
          current_momentum: momentum,
          signal_type: signal_type
        }
      end

      if adx_ok == false
        reasons << "ADX below minimum value (#{ta&.adx})"
        details[:adx] = {
          current_value: ta&.adx,
          min_value: MIN_ADX_VALUE
        }
      end

      {
        passed: reasons.empty?,
        reasons: reasons,
        details: details
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

        # Analyze why strikes were filtered out
        @option_chain[:oc].each do |strike_str, data|
          option = data[side]
          next unless option

          strike_price = strike_str.to_f
          reasons = []

          # Check each filter
          reasons << 'IV zero' if option['implied_volatility'].to_f.zero?
          reasons << 'Price zero' if option['last_price'].to_f.zero?
          reasons << 'Delta low' if option.dig('greeks', 'delta').to_f.abs < min_delta_now
          reasons << 'Deep ITM' if deep_itm_strike?(strike_price, signal_type)
          reasons << 'Deep OTM' if deep_otm_strike?(strike_price, signal_type)
          reasons << 'Outside enhanced ATM range' unless within_enhanced_atm_range?(strike_price, signal_type)

          next unless reasons.any?

          strike_filters[:filters_applied] << {
            strike_price: strike_price,
            reasons: reasons,
            distance_from_atm: (strike_price - atm_strike).abs,
            delta: option.dig('greeks', 'delta').to_f.abs,
            iv: option['implied_volatility'].to_f,
            price: option['last_price'].to_f
          }
        end
      else
        # Show which strikes passed and their characteristics
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
