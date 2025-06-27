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

    def lot_size_for(expiry, dir)
      @lot_size_cache ||= {}
      @lot_size_cache[[expiry, dir]] ||= Instrument.mcx
                                                   .instrument_options_commodity
                                                   .find do |row|
        next unless (m = DISPLAY_RE.match(row.display_name))
        next unless m[:cp].starts_with?(dir.to_s.upcase[0])

        to_date(expiry) == parse_expiry(row.display_name)
      end&.lot_size.to_i
    end

    # ------------------------------------------------------------------
    # helper – insure we always work with Date objects
    # ------------------------------------------------------------------
    def to_date(obj) = obj.is_a?(Date) ? obj : Date.parse(obj)
  end
end
