module Market
  class AnalysisUpdater < ApplicationService
    INTERVAL  = '5'.freeze # 5-minute candles
    PERIODS   = 50 # pull ~4 hours (enough for ATR14)
    SYMBOLS   = %w[NIFTY BANKNIFTY SENSEX].freeze

    # ------------------------------------------------------------------
    # 🗓  Trading-day helpers
    # ------------------------------------------------------------------
    MARKET_OPEN  = Time.zone.parse('09:15')
    MARKET_CLOSE = Time.zone.parse('15:30')

    def call
      SYMBOLS.each { |sym| update_symbol(sym) }
    end

    private

    def update_symbol(symbol)
      inst    = instrument(symbol, segment: 'index')
      candles = fetch_candles(inst)
      return if candles.size < 15

      atr   = atr14(candles)
      close = (candles.last[:close] || candles.last['close']).to_f
      record! symbol, atr, close
      detect_confluence(symbol, candles)
    rescue StandardError => e
      Rails.logger.error "[TA] #{symbol} – #{e.class}: #{e.message}"
    end

    def detect_confluence(symbol, candles)
      signal = Market::ConfluenceDetector.call(symbol: symbol, candles: candles)
      Market::ConfluenceNotifier.call(signal: signal)
    rescue StandardError => e
      Rails.logger.error "[TA] Confluence #{symbol} – #{e.class}: #{e.message}"
    end

    # --- Dhan HQ -------------------------------------------------------------
    def fetch_candles(instrument)
      to_date = latest_trading_day
      from_date = previous_weekday(to_date)

      resp = Dhanhq::API::Historical.intraday(
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: 'INDEX',
        interval: INTERVAL,
        fromDate: from_date.iso8601,
        toDate: to_date.iso8601
      )

      normalise_candles(resp)
    end

    # ------------------------------------------------------------------
    #  Normalise Dhan response ➜ [ {high:, low:, close:}, … ]
    # ------------------------------------------------------------------
    def normalise_candles(resp)
      return [] if resp.blank?

      # 1️⃣ Already an array of candle hashes
      return resp.map { |c| slice_candle(c) } if resp.is_a?(Array)

      # 2️⃣ Hash of arrays
      raise "Unexpected candle format: #{resp.class}" unless resp.is_a?(Hash) && resp['high'].is_a?(Array)

      size = resp['high'].size
      (0...size).map do |i|
        {
          open: resp['open']&.dig(i).to_f,
          high: resp['high'][i].to_f,
          low: resp['low'][i].to_f,
          close: resp['close'][i].to_f,
          timestamp: resp['timestamp']&.dig(i),
          volume: resp['volume']&.dig(i).to_i
        }
      end
    end

    def slice_candle(c)
      {
        open: (c['open']      || c[:open]).to_f,
        high: (c['high']      || c[:high]).to_f,
        low: (c['low'] || c[:low]).to_f,
        close: (c['close'] || c[:close]).to_f,
        timestamp: c['timestamp'] || c[:timestamp],
        volume: (c['volume'] || c[:volume]).to_i
      }
    end

    def index_security_id(symbol)
      Instrument.find_by!(underlying_symbol: symbol, segment: 'index').security_id
    end

    def instrument(symbol, segment: 'index')
      Instrument.find_by!(underlying_symbol: symbol, segment: segment)
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error "[TA] Instrument not found for #{symbol} in segment #{segment}"
      raise
    end

    # --- ATR (simple Wilder’s) ----------------------------------------------
    def atr14(candles)
      trs = candles.each_cons(2).map do |prev, cur|
        [
          (cur[:high] - cur[:low]).abs,
          (cur[:high] - prev[:close]).abs,
          (cur[:low]  - prev[:close]).abs
        ].max
      end.last(14) # use last 14 TRs
      trs.sum / 14.0
    end

    # --- persistence ---------------------------------------------------------
    def record!(symbol, atr, close)
      IntradayAnalysis.where(symbol: symbol, timeframe: '5m').delete_all # keep single row
      IntradayAnalysis.create!(
        symbol: symbol,
        timeframe: '5m',
        atr: atr,
        atr_pct: (atr / close).round(4),
        last_close: close,
        calculated_at: Time.current
      )
      Rails.logger.info "[TA] #{symbol} ATR14 = #{atr.round(2)} (#{(atr / close * 100).round(2)}%)"
    end

    # --- Date helpers --------------------------------------------------------

    def latest_trading_day(now = Time.zone.now)
      d = now.to_date

      # week-end → roll back to Friday
      d -= 1 while d.saturday? || d.sunday?

      # before market open ⇒ use previous weekday
      d = previous_weekday(d) if now < MARKET_OPEN.change(year: d.year, month: d.month, day: d.day)

      d
    end

    def previous_weekday(date)
      d = date - 1.day
      d -= 1 while d.saturday? || d.sunday?
      d
    end
  end
end