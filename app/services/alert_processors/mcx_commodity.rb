module AlertProcessors
  class McxCommodity < Index
    MONTH_MAP = Date::ABBR_MONTHNAMES
                .each_with_index
                .filter_map { |m, i| m && [m.upcase, i] } #  "JAN" => 1
                .to_h.freeze
    DISPLAY_RE = /
      \A
      (?<symbol>[A-Z]+) \s+
      (?<day>\d{1,2}) \s+
      (?<mon>[A-Z]{3}) \s+
      (?<strike>\d+(?:\.\d+)?) \s+
      (?<cp>CALL|PUT)
    \z/x # CRUDEOIL 17 JUL 5250 CALL

    # ------------------------------------------------------------------
    # 1. use display_name → Date helper for the expiry calendar
    # ------------------------------------------------------------------
    def db_expiry_list
      Instrument.mcx.instrument_options_commodity
                .where(underlying_symbol: instrument.underlying_symbol)
                .pluck(:display_name)
                .filter_map { |n| parse_expiry(n) }
                .uniq.sort
    end

    def parse_expiry(name)
      if (m = name.match(/(\d{1,2})\s+([A-Z]{3})/))
        day  = m[1].to_i
        mon  = MONTH_MAP[m[2]] # now an Integer 1-12
        return nil unless mon

        year = Time.zone.today.year
        begin
          Date.new(year, mon, day)
        rescue StandardError
          nil
        end
      elsif (m = name.match(/\b([A-Z]{3})\s+FUT\b/i))
        mon = MONTH_MAP[m[1].upcase]
        return nil unless mon

        year = Time.zone.today.month > mon ? Time.zone.today.year + 1 : Time.zone.today.year
        last_thursday(year, mon)
      end
    end

    # ------------------------------------------------------------------
    # 2. derivative & lot-size helpers – purely regex-based
    # ------------------------------------------------------------------
    def fetch_derivative(strike, expiry, dir)
      Instrument.mcx.instrument_options_commodity.find do |row|
        next unless (m = DISPLAY_RE.match(row.display_name))
        next unless m[:cp].starts_with?(dir.to_s.upcase[0]) # C or P
        next unless to_date(expiry) == parse_expiry(row.display_name)

        (m[:strike].to_f - strike[:strike_price].to_f).abs < 0.01
      end
    end

    MCX_LOT_SIZES = {
      'CRUDEOIL' => 100,
      'CRUDEOILM' => 10,
      'NATURALGAS' => 1250
      # add more as needed
    }.freeze

    def lot_size_for(_expiry, _option_type)
      MCX_LOT_SIZES.fetch(instrument.underlying_symbol, 100) # fallback default
    end

    def calculate_quantity(strike, lot_size)
      lot_size = lot_size.to_i
      price    = strike[:last_price].to_f
      strike_info = "Strike #{strike[:strike_price]} | Last: #{strike[:last_price]}"

      if lot_size.zero? || price <= 0
        log :error, "❗ Invalid sizing inputs (lot=#{lot_size}, price=#{price}) for #{instrument.id} (#{strike_info})"
        return 0
      end

      balance     = available_balance.to_f
      policy      = deployment_policy(balance)
      alloc_cap   = (balance * policy[:alloc_pct]) # ₹ you may deploy in this trade
      per_lot_cost  = price * lot_size

      # If you can't afford a lot at all, bail early
      if per_lot_cost > balance
        log :warn,
            "🚫 Insufficient margin. Required: ₹#{PriceMath.round_tick(per_lot_cost)}, Available: ₹#{PriceMath.round_tick(balance)}. No order placed."
        return 0
      end

      # 1) Allocation constraint: how many lots fit inside alloc_cap?
      max_lots_by_alloc = (alloc_cap / per_lot_cost).floor

      # 2) Risk constraint: cap lots so that (lots * per_lot_risk) <= risk_per_trade_cap
      #    For commodities, use a conservative 5% stop loss
      sl_pct         = 0.05 # 5% stop loss for commodities
      per_lot_risk   = per_lot_cost * sl_pct
      risk_cap       = balance * policy[:risk_per_trade_pct]
      max_lots_by_risk = per_lot_risk.positive? ? (risk_cap / per_lot_risk).floor : 0

      # 3) Affordability constraint: you must at least afford 1 lot
      max_lots_by_afford = (balance / per_lot_cost).floor

      # The final lots are bounded by all three constraints.
      lots = [max_lots_by_alloc, max_lots_by_risk, max_lots_by_afford].min

      # Graceful 1-lot allowance if alloc-bound is 0 but you still can afford & risk allows
      if lots.zero? && per_lot_cost <= balance && per_lot_risk <= risk_cap
        lots = 1
        log :info, "💡 Alloc-band too tight for >0 lots, allowing 1 lot given affordability & risk OK. (#{strike_info})"
      end

      if lots.zero?
        msg = "No size fits constraints. alloc_cap=₹#{PriceMath.round_tick(alloc_cap)}, " \
              "risk_cap=₹#{PriceMath.round_tick(risk_cap)}, per_lot_cost=₹#{PriceMath.round_tick(per_lot_cost)}, " \
              "per_lot_risk=₹#{PriceMath.round_tick(per_lot_risk)}"
        log :warn, "🚫 Sizing → #{msg}"
        return 0
      end

      total_cost = lots * per_lot_cost
      total_risk = lots * per_lot_risk

      log :info, "✅ Sizing decided: #{lots} lot(s) (qty ~ #{lots * lot_size}). " \
                 "Alloc cap: ₹#{PriceMath.round_tick(alloc_cap)}, Risk cap: ₹#{PriceMath.round_tick(risk_cap)}. " \
                 "Per-lot cost: ₹#{PriceMath.round_tick(per_lot_cost)}, Per-lot risk: ₹#{PriceMath.round_tick(per_lot_risk)}. " \
                 "Total cost: ₹#{PriceMath.round_tick(total_cost)}, Total risk: ₹#{PriceMath.round_tick(total_risk)}. " \
                 "(SL%≈#{(sl_pct * 100).round(1)}%)"

      lots * lot_size
    end

    def build_order_payload(strike, derivative)
      {
        transactionType: SIGNAL_TO_SIDE.fetch(alert[:signal_type]),
        orderType: alert[:order_type].to_s.upcase,
        productType: Dhanhq::Constants::MARGIN, # if MCX requires NRML
        validity: Dhanhq::Constants::DAY,
        securityId: derivative&.security_id, # might be nil in MCX
        exchangeSegment: derivative&.exchange_segment || Dhanhq::Constants::MCX,
        quantity: calculate_quantity(strike, lot_size_for(nil, nil))
      }
    end

    # ------------------------------------------------------------------
    # helper – insure we always work with Date objects
    # ------------------------------------------------------------------
    def to_date(obj) = obj.is_a?(Date) ? obj : Date.parse(obj)
  end
end
