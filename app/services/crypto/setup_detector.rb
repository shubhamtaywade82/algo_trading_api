# frozen_string_literal: true

module Crypto
  # Top-down multi-timeframe engine: turns five {Smc::TimeframeReport}s into
  # at most one {Setup}, or nil.
  #
  # The read is the classic ICT sequence, and each timeframe answers exactly
  # one question:
  #
  #   1d / 4h   which way is the market drawing?          → direction
  #   1h        is structure with us, and are we cheap?    → context
  #   15m       is there a POI, and was liquidity taken?   → location
  #   5m        has intent actually shown up?              → trigger
  #
  # Direction is decided by weighted vote rather than by hard gates so a
  # genuine 4h reversal is not thrown away merely for disagreeing with a daily
  # trend it has just begun to end. What is a hard gate: a 5m trigger must
  # exist, both higher timeframes must not oppose the trade, and the levels
  # have to produce an acceptable reward:risk. Everything else is scored, and
  # a thin setup simply fails to reach the threshold.
  class SetupDetector
    # label => [weight, description]. The weights are what make the score
    # meaningful, so they live in one table rather than scattered through the
    # checks.
    WEIGHTS = {
      daily_alignment: 15,
      h4_alignment: 15,
      h1_alignment: 10,
      h1_reversal: 6,
      premium_discount: 10,
      ote: 5,
      m15_poi: 15,
      m15_sweep: 12,
      m5_trigger: 15,
      m5_displacement: 5,
      m5_imbalance: 5,
      m5_confirmation: 4,
      liquidity_target: 5
    }.freeze

    MAX_SCORE = WEIGHTS.values.sum.to_f

    # Bars back within which a signal still counts as "now" on each timeframe.
    H1_REVERSAL_LOOKBACK = 20
    M15_SWEEP_LOOKBACK   = 12
    M5_TRIGGER_LOOKBACK  = 12

    # Buffer beyond the structural low/high, so a stop is not sitting exactly
    # on the level everyone else's is.
    STOP_BUFFER_ATR = 0.3

    def self.call(...) = new(...).call

    def initialize(symbol:, reports:, min_score: nil, min_risk_reward: nil)
      @symbol          = symbol
      @reports         = reports
      @min_score       = min_score || Config.min_score
      @min_risk_reward = min_risk_reward || Config.min_risk_reward
    end

    # @return [Crypto::Setup, nil]
    def call
      return nil unless complete_reports?

      direction = candidate_direction
      return nil if direction.nil?
      return nil if higher_timeframes_oppose?(direction)

      confluences = confluences_for(direction)
      return nil unless triggered?(confluences)

      score = score_for(confluences)
      return nil if score < @min_score

      levels = levels_for(direction)
      return nil if levels.nil?

      build_setup(direction, score, confluences, levels)
    end

    private

    attr_reader :symbol, :reports

    def daily = reports[Config::HTF_TIMEFRAMES[0]]
    def h4    = reports[Config::HTF_TIMEFRAMES[1]]
    def h1    = reports[Config::STRUCTURE_TIMEFRAME]
    def m15   = reports[Config::SETUP_TIMEFRAME]
    def m5    = reports[Config::EXECUTION_TIMEFRAME]

    def complete_reports?
      Config::TIMEFRAMES.all? { |tf| reports[tf].present? && reports[tf].series.size > 20 }
    end

    def price = m5.price

    # --- direction ---------------------------------------------------------

    # Weighted vote across the three context timeframes. A tie means the
    # market has no agreed direction, and no direction means no trade.
    def candidate_direction
      votes = Hash.new(0)
      { daily => 2, h4 => 2, h1 => 1 }.each do |report, weight|
        votes[report.bias] += weight unless report.bias == :neutral
      end

      return nil if votes[:bullish] == votes[:bearish]

      votes[:bullish] > votes[:bearish] ? :bullish : :bearish
    end

    # Fading both higher timeframes at once is not a setup, however good the
    # lower-timeframe picture looks.
    def higher_timeframes_oppose?(direction)
      opposite = direction == :bullish ? :bearish : :bullish
      daily.bias == opposite && h4.bias == opposite
    end

    # --- confluence --------------------------------------------------------

    def confluences_for(direction)
      checks(direction).filter_map do |key, (present, label)|
        next unless present

        { key: key, weight: WEIGHTS.fetch(key), label: label }
      end
    end

    def checks(direction)
      {
        daily_alignment: [daily.bias == direction, "1d structure #{daily.bias}"],
        h4_alignment: [h4.bias == direction, "4h structure #{h4.bias}"],
        h1_alignment: [h1.bias == direction, "1h structure #{h1.bias}"],
        h1_reversal: [h1_reversal?(direction), '1h CHoCH — early trend shift'],
        premium_discount: [h1.premium_discount.favourable?(price, direction), premium_discount_label(direction)],
        ote: [in_ote?(direction), 'Price in OTE (0.62–0.79 retracement)'],
        m15_poi: [m15_poi(direction).present?, m15_poi_label(direction)],
        m15_sweep: [m15_sweep(direction).present?, m15_sweep_label(direction)],
        m5_trigger: [m5_trigger(direction).present?, m5_trigger_label(direction)],
        m5_displacement: [m5.price_action.displacement?(direction), '5m displacement candle'],
        m5_imbalance: [m5_imbalance?(direction), '5m fair value gap left behind'],
        m5_confirmation: [m5_confirmation?(direction), '5m engulfing / rejection wick'],
        liquidity_target: [liquidity_target(direction).present?, liquidity_target_label(direction)]
      }
    end

    def triggered?(confluences)
      confluences.any? { |c| c[:key] == :m5_trigger }
    end

    def score_for(confluences)
      ((confluences.sum { |c| c[:weight] } / MAX_SCORE) * 100).round(1)
    end

    def h1_reversal?(direction)
      h1.structure.recent_event(direction: direction, type: :choch, lookback: H1_REVERSAL_LOOKBACK).present?
    end

    def in_ote?(direction)
      h1.premium_discount.in_ote?(price, direction) || m15.premium_discount.in_ote?(price, direction)
    end

    def m15_poi(direction)
      @m15_poi ||= {}
      @m15_poi[direction] ||= m15.active_poi(direction)
    end

    def m15_sweep(direction)
      @m15_sweep ||= {}
      @m15_sweep[direction] ||= m15.liquidity.recent_sweep(direction, lookback: M15_SWEEP_LOOKBACK)
    end

    def m5_trigger(direction)
      @m5_trigger ||= {}
      @m5_trigger[direction] ||= m5.structure.recent_event(direction: direction, lookback: M5_TRIGGER_LOOKBACK)
    end

    def m5_imbalance?(direction)
      m5.fair_value_gaps.candidates(direction, price).any? { |zone| zone.index >= m5.series.size - 10 }
    end

    def m5_confirmation?(direction)
      m5.price_action.engulfing?(direction) || m5.price_action.rejection?(direction)
    end

    # Where the move is drawn to: resting liquidity beyond the entry, on 15m
    # first and 1h as the extended objective.
    def liquidity_target(direction, report = m15, from = nil)
      from ||= price
      if direction == :bullish
        report.liquidity.target_above(from) || report.structure.next_liquidity_above(from)
      else
        report.liquidity.target_below(from) || report.structure.next_liquidity_below(from)
      end
    end

    # --- levels ------------------------------------------------------------

    def levels_for(direction)
      entry = price
      stop  = stop_for(direction, entry)
      return nil if stop.nil?

      risk = (entry - stop).abs
      return nil unless risk.positive?
      return nil if risk > (m15.atr * Config.max_stop_atr_multiple)

      targets = targets_for(direction, entry, risk)
      rr = ((targets.first - entry).abs / risk).round(2)
      return nil if rr < @min_risk_reward

      { entry: entry, stop: stop, targets: targets, risk: risk, risk_reward: rr }
    end

    # The stop sits beyond whichever structure is protecting the trade: the
    # POI that price reacted from, the low that was swept, or the last 5m
    # swing — whichever is furthest, plus a buffer.
    def stop_for(direction, entry)
      buffer = m5.atr * STOP_BUFFER_ATR
      anchors = stop_anchors(direction)
      return nil if anchors.empty?

      if direction == :bullish
        level = anchors.min - buffer
        level < entry ? level : nil
      else
        level = anchors.max + buffer
        level > entry ? level : nil
      end
    end

    def stop_anchors(direction)
      poi = m15_poi(direction)
      sweep = m15_sweep(direction)
      swing = direction == :bullish ? recent_swing_low : recent_swing_high

      [
        poi && (direction == :bullish ? poi.bottom : poi.top),
        sweep&.level,
        swing
      ].compact
    end

    def recent_swing_low(lookback: 12)
      m5.series.candles.last(lookback).map(&:low).min
    end

    def recent_swing_high(lookback: 12)
      m5.series.candles.last(lookback).map(&:high).max
    end

    # TP1 is the nearest 15m liquidity pool, TP2 the 1h one. Where the pool is
    # too close to be worth the risk, an R-multiple stands in — the point of
    # the target is to be reachable, and a pool half an R away is not a target
    # so much as noise.
    def targets_for(direction, entry, risk)
      sign = direction == :bullish ? 1 : -1

      tp1 = pick_target(liquidity_target(direction, m15, entry), entry + (sign * risk * 1.5), direction)
      tp2 = pick_target(liquidity_target(direction, h1, entry), entry + (sign * risk * 3.0), direction)

      # TP2 has to clear TP1, and an R-multiple measured from *entry* does not
      # guarantee that: where the 15m pool already sits beyond 3R, the 1h
      # fallback lands between entry and TP1 and the alert reads with its
      # targets inverted. Measure the floor from TP1 instead.
      tp2 = pick_target(tp2, tp1 + (sign * risk * 0.75), direction)

      [tp1.round(6), tp2.round(6)]
    end

    # The further of `candidate` and `floor`, in the trade's direction.
    def pick_target(candidate, floor, direction)
      return floor if candidate.nil?

      direction == :bullish ? [candidate, floor].max : [candidate, floor].min
    end

    # --- assembly ----------------------------------------------------------

    def build_setup(direction, score, confluences, levels)
      Setup.new(
        symbol: symbol,
        direction: direction == :bullish ? :long : :short,
        score: score,
        entry: levels[:entry],
        stop: levels[:stop],
        targets: levels[:targets],
        risk: levels[:risk],
        risk_reward: levels[:risk_reward],
        confluences: confluences,
        poi: m15_poi(direction),
        context: context_for(direction)
      )
    end

    def context_for(direction)
      {
        bias: { '1d' => daily.bias, '4h' => h4.bias, '1h' => h1.bias, '15m' => m15.bias, '5m' => m5.bias },
        range_zone: h1.premium_discount.zone(price),
        trigger: m5_trigger(direction)&.to_s,
        sweep: m15_sweep(direction)&.level,
        atr: { '15m' => m15.atr, '5m' => m5.atr }
      }
    end

    def premium_discount_label(direction)
      zone = h1.premium_discount.zone(price)
      side = direction == :bullish ? 'discount' : 'premium'
      "Price in #{zone || side} of the 1h dealing range"
    end

    def m15_poi_label(direction)
      poi = m15_poi(direction)
      return '15m point of interest' if poi.nil?

      state = poi.fresh? ? 'unmitigated' : 'retested'
      "15m #{state} #{poi.kind == :fvg ? 'FVG' : 'order block'} " \
        "#{format_price(poi.bottom)}–#{format_price(poi.top)}"
    end

    def m15_sweep_label(direction)
      sweep = m15_sweep(direction)
      return '15m liquidity sweep' if sweep.nil?

      side = direction == :bullish ? 'sell-side' : 'buy-side'
      "15m #{side} liquidity swept at #{format_price(sweep.level)}"
    end

    def m5_trigger_label(direction)
      event = m5_trigger(direction)
      return '5m structure shift' if event.nil?

      "5m #{event.type.to_s.upcase} through #{format_price(event.level)}"
    end

    def liquidity_target_label(direction)
      target = liquidity_target(direction)
      return 'Liquidity resting beyond entry' if target.nil?

      "Liquidity resting at #{format_price(target)}"
    end

    def format_price(value)
      Formatting.price(value)
    end
  end
end
