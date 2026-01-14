# frozen_string_literal: true

module Strategies
  # Deterministic expiry-day range strategy with kill-switches.
  # This is intentionally not AI-driven.
  class ExpiryRangeStrategy
    START_TIME = { hour: 9, min: 45 }.freeze
    END_TIME   = { hour: 14, min: 30 }.freeze

    MIN_PREMIUM = 25.0

    def self.call(md:, series_5m:, vix_snapshot:)
      new(md: md, series_5m: series_5m, vix_snapshot: vix_snapshot).call
    end

    def initialize(md:, series_5m:, vix_snapshot:)
      @md = md
      @series_5m = series_5m
      @vix = vix_snapshot
    end

    def call
      return no_trade('Not expiry day', market_bias: 'UNCLEAR') unless expiry_day?
      return no_trade('Time window closed', market_bias: 'UNCLEAR') unless time_window_ok?
      return no_trade('VIX regime invalid', market_bias: 'UNCLEAR') unless vix_ok?
      return no_trade('Trend/acceptance detected (no range edge)', market_bias: 'UNCLEAR') if acceptance_kill_switch?

      return wait if inside_range_without_edge?

      return buy_call if discount_rejection?
      return buy_put if premium_rejection?

      no_trade('No edge location (not at AVRZ extremes)', market_bias: 'RANGE')
    end

    private

    attr_reader :md, :series_5m, :vix

    def expiry_day?
      exp = md[:expiry].to_s
      return false if exp.blank?

      Date.parse(exp) == MarketCalendar.today_or_last_trading_day
    rescue Date::Error
      false
    end

    def time_window_ok?
      now = md[:ts] || Time.zone.now
      start = now.change(**START_TIME)
      finish = now.change(**END_TIME)
      now >= start && now <= finish
    end

    def vix_ok?
      return false if vix.nil?
      return false unless vix.pdh.to_f.positive? && vix.pwl.to_f.positive?

      vix.range_regime?
    end

    def acceptance_kill_switch?
      range = avrz_15m
      return true if range.blank?

      closes = series_5m.closes.last(3).map(&:to_f)
      return false if closes.size < 3

      above = closes.all? { |c| c > range[:high].to_f }
      below = closes.all? { |c| c < range[:low].to_f }
      above || below
    end

    def inside_range_without_edge?
      range = avrz_15m
      return true if range.blank?

      close = series_5m.closes.last.to_f
      close.between?(range[:low].to_f, range[:high].to_f) && !discount_rejection? && !premium_rejection?
    end

    def premium_rejection?
      range = avrz_15m
      return false if range.blank?

      c = series_5m.candles.last
      c.high.to_f > range[:high].to_f && c.close.to_f < range[:high].to_f
    end

    def discount_rejection?
      range = avrz_15m
      return false if range.blank?

      c = series_5m.candles.last
      c.low.to_f < range[:low].to_f && c.close.to_f > range[:low].to_f
    end

    def buy_call
      strike, premium_ref = pick_premium(:CE)
      return no_trade('Option premium unavailable', market_bias: 'RANGE') unless premium_ref
      return no_trade('Premium too low (theta trap)', market_bias: 'RANGE') if premium_ref < MIN_PREMIUM

      entry = premium_ref.round(2)
      stop_loss = (entry * 0.75).round(2)
      target = (entry + (entry - stop_loss) * 1.5).round(2)
      rr = ((target - entry) / (entry - stop_loss)).round(2)

      inv_level = md.dig(:smc, :m15)&.last_swing_low&.dig(:price) || avrz_15m[:low]
      vwap = md.dig(:value, :m15, :vwap) || avrz_15m[:mid]

      <<~MSG.strip
        Decision: BUY
        Instrument: #{md[:symbol]}
        Bias: BULLISH

        Option:
        - Type: CE
        - Strike: #{strike}
        - Expiry: #{md[:expiry]}

        Execution:
        - Entry Premium: #{entry}
        - Stop Loss Premium: #{stop_loss}
        - Target Premium: #{target}
        - Risk Reward: #{rr}

        Underlying Context:
        - Spot Above: #{vwap.to_f.round(2)} (VWAP reference)
        - Invalidation Below: #{inv_level.to_f.round(2)} (15m structure)

        Exit Rules:
        - SL Hit on premium
        - OR Spot closes below #{inv_level.to_f.round(2)} on 5m
        - OR Spot fails to hold above VWAP for 2 consecutive 5m candles

        Reason: Expiry range day with discount rejection back into AVRZ.
      MSG
    end

    def buy_put
      strike, premium_ref = pick_premium(:PE)
      return no_trade('Option premium unavailable', market_bias: 'RANGE') unless premium_ref
      return no_trade('Premium too low (theta trap)', market_bias: 'RANGE') if premium_ref < MIN_PREMIUM

      entry = premium_ref.round(2)
      stop_loss = (entry * 0.75).round(2)
      target = (entry + (entry - stop_loss) * 1.5).round(2)
      rr = ((target - entry) / (entry - stop_loss)).round(2)

      inv_level = md.dig(:smc, :m15)&.last_swing_high&.dig(:price) || avrz_15m[:high]
      vwap = md.dig(:value, :m15, :vwap) || avrz_15m[:mid]

      <<~MSG.strip
        Decision: BUY
        Instrument: #{md[:symbol]}
        Bias: BEARISH

        Option:
        - Type: PE
        - Strike: #{strike}
        - Expiry: #{md[:expiry]}

        Execution:
        - Entry Premium: #{entry}
        - Stop Loss Premium: #{stop_loss}
        - Target Premium: #{target}
        - Risk Reward: #{rr}

        Underlying Context:
        - Spot Below: #{vwap.to_f.round(2)} (VWAP reference)
        - Invalidation Above: #{inv_level.to_f.round(2)} (15m structure)

        Exit Rules:
        - SL Hit on premium
        - OR Spot closes above #{inv_level.to_f.round(2)} on 5m
        - OR Spot reclaims VWAP and holds for 2 candles

        Reason: Expiry range day with premium rejection back into AVRZ.
      MSG
    end

    def wait
      range = avrz_15m
      vwap = md.dig(:value, :m15, :vwap)

      <<~MSG.strip
        Decision: WAIT
        Instrument: #{md[:symbol]}
        Bias: RANGE (15m)
        No Trade Because:
        - Price inside 15m AVRZ
        - No confirmed rejection at premium/discount edge
        Trigger Conditions:
        - Rejection wick + close back inside AVRZ at #{range[:low].to_f.round(2)} or #{range[:high].to_f.round(2)}
        - 5m holds around VWAP #{vwap.to_f.round(2)} without acceptance outside AVRZ
        Preferred Option (If Triggered):
        - Type: CE|PE
        - Strike Zone: ATM
        - Expected Premium Zone: >= #{MIN_PREMIUM}
        Reason: Range regime intact but edge location not confirmed.
      MSG
    end

    def no_trade(reason, market_bias:)
      range = avrz_15m

      reevaluate = [
        "Price returns inside AVRZ (#{range[:low].to_f.round(2)}–#{range[:high].to_f.round(2)}) after acceptance",
        'VIX slope flattens and stays within PDH/PWL'
      ]

      <<~MSG.strip
        Decision: NO_TRADE
        Instrument: #{md[:symbol]}
        Market Bias: #{market_bias}
        Reason: #{reason}
        Risk Note: No edge for options buying
        Re-evaluate When:
        - #{reevaluate.join("\n- ")}
      MSG
    end

    def avrz_15m
      md.dig(:value, :m15, :avrz) || {}
    end

    def pick_premium(option_type)
      atm = md.dig(:options, :atm) || {}
      strike = atm[:strike].to_i

      contract =
        if option_type == :CE
          atm[:call] || {}
        else
          atm[:put] || {}
        end

      ask = contract['top_ask_price'] || contract[:top_ask_price]
      ltp = contract['last_price'] || contract[:last_price]

      [strike, Float(ask || ltp, exception: false)]
    end
  end
end

