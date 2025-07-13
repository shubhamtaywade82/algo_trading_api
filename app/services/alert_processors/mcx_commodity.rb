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

        m[:strike].to_f == strike[:strike_price].to_f
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
      price = strike[:last_price].to_f
      per_lot_cost = price * lot_size

      # Here you can keep the same affordability logic:
      max_investment = (available_balance * 0.3)

      lots = (max_investment / per_lot_cost).floor
      if lots.zero? && per_lot_cost <= available_balance
        lots = 1
        log :info, "💡 Not enough margin for 30% allocation, but can buy 1 lot. Per lot cost: ₹#{per_lot_cost.round(2)}."
      elsif lots.zero?
        log :warn, "🚫 Insufficient margin. Required: ₹#{per_lot_cost.round(2)}. No order placed."
        return 0
      else
        log :info, "✅ Allocating #{lots} lot(s). Per lot cost: ₹#{per_lot_cost.round(2)}."
      end

      lots # * lot_size
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
