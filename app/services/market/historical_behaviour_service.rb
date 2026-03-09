# frozen_string_literal: true

module Market
  # Service for analyzing historical intraday ATM options behaviour.
  # Based on the original algo_trading_system rake task but refactored for SOLID/Rails.
  class HistoricalBehaviourService < ApplicationService
    include MarketCalendar

    SESSIONS = {
      'Morning'   => (9 * 60 + 15)..(11 * 60),
      'Midday'    => (11 * 60 + 1)..(13 * 60),
      'Afternoon' => (13 * 60 + 1)..(15 * 60 + 30)
    }.freeze

    def initialize(weeks: 12, symbol: 'NIFTY', interval: '5')
      @weeks = weeks.to_i
      @symbol = symbol.upcase
      @interval = interval
    end

    def call
      instrument = find_instrument
      return { error: "Instrument not found for #{@symbol}" } unless instrument

      @lot_size = resolve_lot_size(instrument)

      windows = expiry_windows(@weeks, @symbol)
      results = []

      windows.each do |window|
        analysis = analyze_window(instrument, window)
        results << analysis if analysis
        # Respect rate limits
        sleep 0.5
      end

      {
        symbol: @symbol,
        weeks: @weeks,
        interval: @interval,
        lot_size: @lot_size,
        expiry_cycles: results,
        summary: aggregate_summary(results)
      }
    end

    private

    def find_instrument
      Instrument.find_by(underlying_symbol: @symbol) || Instrument.find_by(symbol_name: @symbol)
    end

    def resolve_lot_size(instrument)
      # If the instrument itself has a valid lot_size > 1 (e.g. some stocks), use it.
      return instrument.lot_size if instrument.lot_size.to_i > 1

      # For Indices, check the first associated derivative to find the tradable lot size.
      d_lot = instrument.derivatives.first&.lot_size
      return d_lot if d_lot.to_i > 1

      # Fallback defaults
      case @symbol
      when 'NIFTY' then 25
      when 'BANKNIFTY' then 15
      when 'SENSEX' then 10
      else 1
      end
    end

    def last_expiry_day(date, symbol)
      # NIFTY = Thursday (4), SENSEX = Friday (5), BANKNIFTY = Wednesday (3)
      target_wday = case symbol
                    when 'SENSEX' then 5
                    when 'NIFTY' then 4
                    when 'BANKNIFTY' then 3
                    else 4
                    end
      diff = (date.wday - target_wday) % 7
      date - diff
    end

    def expiry_windows(weeks, symbol)
      today = Time.zone.today
      current_expiry = last_expiry_day(today, symbol)
      weeks.times.map do |i|
        expiry = current_expiry - (i * 7)
        { expiry: expiry, from: expiry - 6, to: expiry }
      end.reverse
    end

    def analyze_window(instrument, window)
      from_str = window[:from].to_s
      to_str   = window[:to].to_s

      # Note: We need a way to fetch ATM strikes for these dates.
      spot_bars = instrument.historical_ohlc(from_date: from_str, to_date: to_str)
      return nil if spot_bars.blank? || spot_bars['close'].blank?

      atm_strike = calculate_atm_strike(spot_bars['open'].first, @symbol)

      # Fetch CE and PE for this strike and expiry.
      ce_data = fetch_option_data(instrument, atm_strike, 'CALL', window[:expiry], from_str, to_str)
      pe_data = fetch_option_data(instrument, atm_strike, 'PUT',  window[:expiry], from_str, to_str)

      {
        expiry: window[:expiry],
        from: from_str,
        to: to_str,
        strike: atm_strike,
        ce: cycle_stats(ce_data, spot_bars),
        pe: cycle_stats(pe_data, spot_bars)
      }
    end

    def calculate_atm_strike(spot, symbol)
      step = case symbol
             when 'SENSEX', 'BANKNIFTY' then 100
             else 50 # NIFTY, FINNIFTY, etc.
             end
      (spot.to_f / step).round * step
    end

    def fetch_option_data(instrument, _strike, type, _expiry, from, to)
      # Use rolling_ohlc to fetch actual option premiums from Dhan's rolling options API.
      Dhan::MarketDataService.new(instrument).rolling_ohlc(
        from_date: from,
        to_date: to,
        interval: @interval,
        strike: 'ATM',
        option_type: type,
        expiry_flag: 'WEEK',
        expiry_code: 1
      )
    end

    def cycle_stats(bars, _spot_bars)
      return nil if bars.blank? || bars['close'].blank?

      opens = bars['open'] || []
      highs = bars['high'] || []
      lows = bars['low'] || []
      closes = bars['close'] || []

      return nil if opens.empty?

      entry   = opens.first.to_f
      max_h   = highs.max.to_f
      min_l   = lows.min.to_f
      final_c = closes.last.to_f

      peak_idx = highs.index(max_h)
      post_peak_lows = lows[peak_idx..-1]
      pullback_l = post_peak_lows.min.to_f

      {
        entry: entry.round(2),
        max_high: max_h.round(2),
        max_low: min_l.round(2),
        exit: final_c.round(2),
        max_gain_pct: pct(max_h, entry),
        max_loss_pct: pct(min_l, entry),
        open_to_close_pct: pct(final_c, entry),
        post_peak_retrace: pct(pullback_l, max_h)
      }
    end

    def pct(v, b)
      return 0.0 if b.to_f.zero?
      ((v - b) / b.to_f * 100).round(2)
    end

    def aggregate_summary(results)
      valid_ce = results.map { |r| r[:ce] }.compact
      valid_pe = results.map { |r| r[:pe] }.compact
      
      {
        ce: compute_metrics(valid_ce),
        pe: compute_metrics(valid_pe)
      }
    end

    def compute_metrics(stats_array)
      return {} if stats_array.empty?

      keys = %i[max_gain_pct max_loss_pct open_to_close_pct post_peak_retrace]
      
      summary = { count: stats_array.size }

      keys.each do |key|
        values = stats_array.map { |s| s[key] }.compact
        summary[key] = (values.sum / values.size).round(2) if values.any?
      end

      # Add Absolute P&L per lot based on Open-to-Close
      avg_oc_pct = summary[:open_to_close_pct] || 0.0
      avg_entry = stats_array.map { |s| s[:entry] }.compact.then { |v| v.sum / v.size }
      
      summary[:avg_pnl_per_lot] = (avg_entry * (avg_oc_pct / 100.0) * @lot_size).round(2)
      
      summary
    end
  end
end
