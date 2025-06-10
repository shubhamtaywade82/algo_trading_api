# frozen_string_literal: true

module Scanners
  class SwingScreenerService < ApplicationService
    DONCHIAN_PERIOD = 20
    EMA_PERIOD = 200
    RSI_PERIOD = 14
    VOLUME_SMA_PERIOD = 20
    MIN_CANDLES = [DONCHIAN_PERIOD, EMA_PERIOD, RSI_PERIOD, VOLUME_SMA_PERIOD].max
    API_SLEEP = 0.2 # max 5 requests/second

    def initialize(limit: 300, notify: true)
      @candidates = Instrument
                    .nse
                    .segment_equity.where(instrument_type: %w[ES ETF])
                    .limit(limit)
      @notify = notify
    end

    def call
      @candidates.each do |instrument|
        sleep(API_SLEEP) # throttle to 5 API/sec
        candles = safe_fetch_ohlc(instrument)
        next unless valid_candles?(candles)

        closes  = candles.pluck(:close)
        highs   = candles.pluck(:high)
        lows    = candles.pluck(:low)
        volumes = candles.pluck(:volume)

        price_series = candles.map { |c| { date_time: c[:time], close: c[:close] } }

        ema_values = Scanners::Talib.ema(price_series, EMA_PERIOD)
        rsi_values = Scanners::Talib.rsi(price_series, RSI_PERIOD)

        ema = ema_values.last
        rsi = rsi_values.last

        volume_avg = volumes.last(VOLUME_SMA_PERIOD).sum / VOLUME_SMA_PERIOD.to_f
        price   = closes.last
        high20  = highs.last(DONCHIAN_PERIOD).max
        low20   = lows.last(DONCHIAN_PERIOD).min
        vol     = volumes.last

        setup_type = nil
        trigger_level = nil

        Rails.logger.debug { "#{instrument.symbol_name}  #{price}, #{high20}, #{ema}, #{rsi}, #{vol}, #{volume_avg}" }
        if price > high20 && price > ema && rsi.between?(50, 70) && vol > 1.5 * volume_avg
          setup_type = 'breakout'
          trigger_level = high20
        elsif price <= low20 && rsi < 30 && price > ema && vol > volume_avg
          setup_type = 'reversal'
          trigger_level = low20 * 1.03
        else
          next # Not a valid setup
        end

        explanation = Openai::SwingExplainer.explain(instrument.symbol_name, price:, rsi:, ema:, high20:, low20:, setup_type:)

        SwingPick.create!(
          instrument: instrument,
          setup_type: setup_type,
          trigger_price: trigger_level,
          close_price: price,
          ema: ema,
          rsi: rsi,
          volume: vol,
          analysis: explanation,
          status: 'pending'
        )

        next unless @notify

        notify(
          "📈 *#{setup_type.upcase}* setup detected for *#{instrument.symbol_name}* (₹#{price.round(2)})\n\n🧠 _#{explanation}_",
          tag: 'SWING_PICK'
        )
      rescue StandardError => e
        Rails.logger.warn("Screener error for #{instrument.symbol_name}: #{e.message}")
        next
      end
    end

    private

    def safe_fetch_ohlc(instrument)
      payload = {
        securityId: instrument.security_id,
        exchangeSegment: instrument.exchange_segment,
        instrument: instrument.instrument.upcase,
        expiryCode: 0,
        fromDate: 365.days.ago.to_date.to_s,
        toDate: Time.zone.today.to_s
      }

      raw = Dhanhq::API::Historical.daily(payload)

      return [] unless raw.is_a?(Hash) && raw['close']

      raw['close'].each_index.map do |i|
        {
          close: raw['close'][i],
          high: raw['high'][i],
          low: raw['low'][i],
          open: raw['open'][i],
          volume: raw['volume'][i],
          time: Time.zone.at(raw['timestamp'][i])
        }
      end
    rescue StandardError => e
      Rails.logger.error("Failed to fetch daily OHLC for #{instrument.symbol_name}: #{e.message}")
      []
    end

    def valid_candles?(candles)
      candles.is_a?(Array) && candles.size >= MIN_CANDLES
    end
  end
end
