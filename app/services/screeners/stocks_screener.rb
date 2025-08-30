# frozen_string_literal: true

module Screeners
  class StocksScreener < ApplicationService
    DEFAULT_FRAME       = '15m'
    DEFAULT_LOOKBACK    = 20
    DEFAULT_LIMIT       = 25
    DEFAULT_MIN_PRICE   = 80.0
    DEFAULT_MIN_AVG_VOL = 75_000
    DEFAULT_OPTIONABLE  = true

    # Entry points:
    #   - symbols: %w[RELIANCE TCS INFY]               # ad-hoc list
    #   - watch_list: 'my_list'                        # persistent list
    #   - otherwise fallback to all NSE equities       # filtered by price/volume
    def initialize(
      symbols: nil,
      watch_list: nil,
      frame: DEFAULT_FRAME,
      lookback: DEFAULT_LOOKBACK,
      limit: DEFAULT_LIMIT,
      min_price: DEFAULT_MIN_PRICE,
      min_avg_vol: DEFAULT_MIN_AVG_VOL,
      optionable: DEFAULT_OPTIONABLE,
      session: :live,
      push_to_telegram: true
    )
      @symbols    = Array(symbols).presence
      @watch_list = watch_list&.to_s&.strip
      @frame      = frame
      @lookback   = lookback.to_i
      @limit      = limit.to_i
      @min_price  = min_price.to_f
      @min_avgvol = min_avg_vol.to_i
      @optionable = optionable
      @session    = session.to_sym
      @push_tg    = push_to_telegram
    end

    class << self
      def call(**kw) = new(**kw).call
    end

    def call
      rows = build_rows
      md   = {
        ts: Time.current,
        session: @session,
        frame: @frame,
        lookback: @lookback,
        rules: {
          min_price: @min_price,
          min_avg_vol: @min_avgvol,
          optionable: @optionable,
          limit: @limit
        },
        stocks: rows
      }

      prompt = PromptBuilder.build_prompt(md)
      Rails.logger.debug(prompt)

      text = Openai::ChatRouter.ask!(
        prompt,
        system: 'You are an elite Indian equities screener for intraday & swing candidates. Be concise, desk-ready.'
      )

      push_telegram(text, md) if @push_tg
      text
    rescue StandardError => e
      Rails.logger.error "[StocksScreener] ❌ #{e.class} – #{e.message}"
      nil
    end

    # ------------------------------------------------------------------
    private

    def universe_scope
      Instrument.where(exchange: :nse, segment: :equity)
    end

    def resolve_instruments
      # 1) explicit symbols
      if @symbols.present?
        return universe_scope.where(symbol_name: @symbols)
                             .or(universe_scope.where(underlying_symbol: @symbols))
      end

      # 2) watch list by name
      if @watch_list.present? && defined?(WatchList)
        wl = WatchList.includes(:instruments).find_by(name: @watch_list, active: true)
        return wl&.instruments || Instrument.none
      end

      # 3) fallback: all NSE equities (you can add more coarse pre-filters here)
      universe_scope
    end

    def optionable?(inst)
      # Cheap check: any option contract for same underlying
      Derivative.exists?(underlying_symbol: inst.underlying_symbol, instrument: 'OPTSTK')
    rescue StandardError
      false
    end

    def build_rows
      rows = []
      resolve_instruments.find_each do |inst|
        snap = safe_stock_snapshot(inst)
        next if snap.blank?
        next if snap[:ltp].to_f < @min_price
        next if snap.dig(:indicators, :avg_vol_20).to_i < @min_avgvol
        next if @optionable && !optionable?(inst)

        rows << snap
        break if rows.size >= (@limit * 2) # gather a bit more; LLM trims
      end
      rows
    end

    def safe_stock_snapshot(inst)
      series = safe { inst.candle_series(interval: @frame.delete_suffix('m')) }
      return if series.blank? || series.candles.blank?

      # Choose latest/previous bar by session
      if @session == :live
        co = series.opens.last
        ch = series.highs.last
        cl = series.lows.last
        cc = series.closes.last
        cv = series.candles.last.volume
      else
        co = series.opens.second_to_last
        ch = series.highs.second_to_last
        cl = series.lows.second_to_last
        cc = series.closes.second_to_last
        cv = series.candles[-2].volume
      end

      prev = previous_daily_ohlc(inst)

      atr    = series.atr[:atr]
      atrpct = atr.to_f.positive? ? (atr.to_f / cc.to_f * 100.0) : 0.0
      rsi    = series.rsi[:rsi]
      macd   = series.macd
      boll   = series.bollinger_bands(period: 20)
      st_sig = series.supertrend_signal

      hi20   = series.recent_highs(20)[:highs].max
      lo20   = series.recent_lows(20)[:lows].min
      liq_up = series.liquidity_grab_up?(lookback: 20)[:liquidity_grab_up]
      liq_dn = series.liquidity_grab_down?(lookback: 20)[:liquidity_grab_down]

      avg_vol_20 = begin
        vols = series.candles.last(@lookback).map(&:volume)
        (vols.sum / [vols.size, 1].max).to_i
      end

      rel_vol = avg_vol_20.zero? ? 0.0 : (cv.to_f / avg_vol_20.to_f)

      {
        symbol: inst.symbol_name,
        name: inst.display_name || inst.symbol_name,
        ltp: cc.to_f.round(2),
        ohlc: { open: co.to_f.round(2), high: ch.to_f.round(2), low: cl.to_f.round(2), close: cc.to_f.round(2), volume: cv.to_i },
        prev_day: prev, # may be nil
        indicators: {
          atr14: atr.to_f,
          atr_pct: atrpct.to_f,
          rsi14: rsi.to_f,
          macd: { macd: macd[:macd].to_f, signal: macd[:signal].to_f, hist: macd[:hist].to_f },
          boll: { upper: boll[:upper].to_f, middle: boll[:middle].to_f, lower: boll[:lower].to_f },
          supertrend: st_sig,
          hi20: hi20.to_f, lo20: lo20.to_f,
          liq_up: !!liq_up, liq_dn: !!liq_dn,
          rel_vol: rel_vol.to_f, avg_vol_20: avg_vol_20
        }
      }
    rescue StandardError => e
      Rails.logger.warn "[StocksScreener] ⚠️ #{inst.symbol_name} – #{e.class}: #{e.message}"
      nil
    end

    def previous_daily_ohlc(inst)
      Rails.cache.fetch("pd-ohlc:#{inst.id}", expires_in: 15.minutes) do
        to_date   = MarketCalendar.today_or_last_trading_day
        from_date = MarketCalendar.last_trading_day(from: to_date - 1)
        bars = inst.historical_ohlc(from_date: from_date.to_s, to_date: to_date.to_s)
        next nil if bars.blank?

        { open: bars['open'].last.to_f.round(2),
          high: bars['high'].last.to_f.round(2),
          low: bars['low'].last.to_f.round(2),
          close: bars['close'].last.to_f.round(2) }
      end
    end

    def push_telegram(text, md)
      hdr = <<~HDR
        🧭 *Stocks Screener* (#{@session.to_s.humanize}, #{@frame}, Lkb #{@lookback})
        Rules: min ₹#{@min_price}, avgVol≥#{@min_avgvol}, optionable=#{@optionable}
        Source: #{@symbols.present? ? "Symbols(#{@symbols.size})" : (@watch_list || 'All NSE Equities')}
      HDR
      TelegramNotifier.send_message(hdr)
      TelegramNotifier.send_message(text)
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.warn "[StocksScreener] safe rescue: #{e.class} – #{e.message}"
      nil
    end
  end
end
