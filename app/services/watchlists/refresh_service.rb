# frozen_string_literal: true

module Watchlists
  class RefreshService < ApplicationService
    DEFAULTS = {
      min_price: 80.0,
      min_avg_vol: 75_000,
      min_turnover: 20_000_000, # ₹2cr
      atr_pct_min: 0.004,
      atr_pct_max: 0.03,
      rel_vol_min_intraday: 1.2,
      batch_size: 400,
      limit: 120 # keep watchlist reasonably sized
    }.freeze

    def initialize(name:, kind:, timeframe:, prune: true, limits: {}, thresholds: {})
      @name       = name.to_s
      @kind       = kind.to_s # intraday/swing/long_term
      @timeframe  = timeframe.to_s # '15m' | '1d' (we can add '60m' later)
      @prune      = prune
      @cfg        = begin
        DEFAULTS.merge(thresholds.symbolize_keys)
      rescue StandardError
        DEFAULTS
      end
      @limit = (limits[:limit] || DEFAULTS[:limit]).to_i
    end

    def call
      wl = Watchlist.find_or_create_by!(name: @name) do |w|
        w.kind = @kind
        w.timeframe = @timeframe
        w.active = true
        w.meta = { created_by: 'screener', thresholds: @cfg }
      end
      wl.update!(kind: @kind, timeframe: @timeframe)

      selected = scan_universe # array of {instrument:, score:, metrics:, bucket:}
      upsert_items(wl, selected.first(@limit))
      prune_items(wl, selected.map { _1[:instrument].id }) if @prune
      wl.touch
      true
    end

    private

    def scan_universe
      out = []
      scope = Instrument.nse.instrument_equity

      scope.in_batches(of: @cfg[:batch_size]) do |batch|
        batch.each do |inst|
          snap = snapshot(inst) # compute from series quickly
          next unless snap && liquid?(snap)

          cand = case @kind
                 when 'intraday'
                   intraday_candidate(snap)
                 when 'swing'
                   swing_candidate(snap)
                 when 'long_term'
                   long_term_candidate(snap)
                 else
                   nil
                 end

          next unless cand

          out << build_result(inst, snap, cand[:score], cand[:bucket], cand[:extras])
        end
      end

      # rank high→low by score
      out.sort_by { |h| -h[:score].to_f }
    end

    # ───────────────────────────────────────────────────────────
    # Series snapshot (fast path) — uses your InstrumentCandleAccessors
    # ───────────────────────────────────────────────────────────
    def snapshot(inst)
      series =
        case @timeframe
        when '15m' then safe { inst.candle_series(interval: '15') }
        when '1d'  then safe { inst.historical_ohlc }
        else            safe { inst.candle_series(interval: '15') }
        end
      return nil unless series&.candles&.present?

      close = series.closes.last.to_f
      vol   = series.candles.last.volume.to_i
      atr   = series.atr[:atr].to_f
      rsi   = series.rsi[:rsi].to_f
      macd  = series.macd
      bb    = series.bollinger_bands(period: 20)

      ema20 = series.moving_average(20)[:ema].to_f
      ema50 = series.moving_average(50)[:ema].to_f
      sma50 = series.moving_average(50)[:sma].to_f
      sma200 = series.moving_average(200)[:sma].to_f
      st = series.supertrend_signal

      vols = series.candles.last(20).map(&:volume)
      avgv = vols.sum / [vols.size, 1].max
      relv = avgv.zero? ? 0.0 : vol.to_f / avgv.to_f

      {
        close: close, vol: vol, avg_vol20: avgv, rel_vol: relv,
        atr14: atr, rsi14: rsi,
        macd_hist: macd[:hist].to_f, macd: macd[:macd].to_f, macd_signal: macd[:signal].to_f,
        boll_upper: bb[:upper].to_f, boll_middle: bb[:middle].to_f, boll_lower: bb[:lower].to_f,
        ema20: ema20, ema50: ema50, sma50: sma50, sma200: sma200,
        supertrend: st || 'neutral'
      }
    rescue StandardError => e
      Rails.logger.debug { "[WatchlistRefresh] #{inst.symbol_name} #{e.class}: #{e.message}" }
      nil
    end

    # ───────────────────────────────────────────────────────────
    # Gates & scoring
    # ───────────────────────────────────────────────────────────
    def liquid?(s)
      s[:close] >= @cfg[:min_price] &&
        s[:avg_vol20].to_i >= @cfg[:min_avg_vol] &&
        (s[:close] * s[:avg_vol20]) >= @cfg[:min_turnover]
    end

    def atr_window?(s, min: @cfg[:atr_pct_min], max: @cfg[:atr_pct_max])
      return false if s[:atr14] <= 0 || s[:close] <= 0

      pct = s[:atr14] / s[:close]
      pct >= min && pct <= max
    end

    def intraday_candidate(s)
      return nil unless @timeframe == '15m'
      return nil unless atr_window?(s)
      return nil unless s[:rel_vol] >= @cfg[:rel_vol_min_intraday]
      return nil if s[:supertrend] == 'neutral'
      return nil if s[:macd_hist].abs <= 0.0

      # score: rel vol + momentum + band proximity
      near_lower = band_proximity_lower(s)
      score = (1.2 * s[:rel_vol].to_f) + (0.8 * s[:macd_hist].to_f) + (0.4 * near_lower)
      { score: score, bucket: 'intraday', extras: {} }
    end

    def swing_candidate(s)
      return nil unless @timeframe == '1d'
      return nil unless atr_window?(s, min: 0.005, max: 0.04)
      return nil if s[:macd_hist].abs <= 0.0

      disc200 = discount200(s)
      rsi_mid = s[:rsi14].between?(45, 60) ? 0.5 : 0.0
      score = (1.0 * s[:macd_hist].to_f) + (0.8 * disc200) + (0.4 * rsi_mid)
      { score: score, bucket: 'swing', extras: {} }
    end

    def long_term_candidate(s)
      return nil unless @timeframe == '1d'

      vs = value_score(s)
      return nil unless vs > 0.8

      { score: vs, bucket: 'long_term', extras: { value_score: vs } }
    end

    def discount200(s)
      sma200 = s[:sma200].to_f
      sma200.positive? ? (sma200 - s[:close].to_f) / sma200 : 0.0
    end

    def band_proximity_lower(s)
      lower = s[:boll_lower].to_f
      mid = s[:boll_middle].to_f
      c = s[:close].to_f
      return 0.0 if c >= mid || (mid - lower).zero?

      (1.0 - ((c - lower) / (mid - lower))).clamp(0.0, 1.0)
    end

    def value_score(s)
      disc200 = discount200(s)
      near_lower = band_proximity_lower(s)
      momentum_up = [s[:macd_hist].to_f, 0].max
      rsi_band = s[:rsi14].between?(32, 48) ? 1.0 : 0.0
      st_bonus = s[:supertrend] == 'buy' ? 0.25 : 0.0
      (1.5 * disc200) + (1.0 * near_lower) + (0.8 * momentum_up) + (0.5 * rsi_band) + st_bonus
    end

    # ───────────────────────────────────────────────────────────
    # Upsert/prune
    # ───────────────────────────────────────────────────────────
    def build_result(inst, s, score, bucket, extras)
      {
        instrument: inst,
        score: score,
        bucket: bucket,
        metrics: s.merge(score: score).merge(extras || {})
      }
    end

    def upsert_items(wl, arr)
      # rank assignment
      arr.each_with_index do |row, i|
        inst = row[:instrument]
        flags = derivative_flags(inst)

        it = WatchlistItem.find_or_initialize_by(watchlist: wl, instrument: inst)
        it.rank = i + 1
        it.bucket = row[:bucket]
        it.metrics = row[:metrics]
        it.last_scored_at = Time.zone.now
        it.has_derivatives = flags[:has_derivatives]
        it.has_options     = flags[:has_options]
        it.has_futures     = flags[:has_futures]
        it.save!
      end
    end

    def prune_items(wl, keep_ids)
      wl.watchlist_items.where.not(instrument_id: keep_ids).delete_all
    end

    def derivative_flags(inst)
      # Cheap DB checks; index derivatives.instrument, derivatives.underlying_symbol for speed
      under = inst.underlying_symbol
      has_opt = Derivative.exists?(underlying_symbol: under, instrument: 'OPTSTK')
      has_fut = Derivative.exists?(underlying_symbol: under, instrument: 'FUTSTK')

      { has_derivatives: has_opt || has_fut, has_options: has_opt, has_futures: has_fut }
    rescue StandardError
      { has_derivatives: false, has_options: false, has_futures: false }
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.debug { "[WatchlistRefresh] #{e.class}: #{e.message}" }
      nil
    end
  end
end
