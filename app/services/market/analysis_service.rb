# frozen_string_literal: true

#
# Runs a single AI-powered market analysis cycle for **one** index / equity.
#
# Minimal API:
#   • symbol  – “NIFTY”, “BANKNIFTY”, “INFY”… (mandatory)
#   • segment – :index / :equity / :derivatives   (defaults to :index)
#
# Everything else (expiry date, exchange, candle-frame, etc.) is discovered
# automatically from the `Instrument` table or falls back to the DhanHQ REST
# endpoints already wrapped in the `Instrument` model.
#
# Example (in console):
#   Market::AnalysisService.call('NIFTY')                 # default = 1-day frame
#   Market::AnalysisService.call('BANKNIFTY', candle: '5m')
#
module Market
  class AnalysisService < ApplicationService
    TELEGRAM_TAG   = '📈 Analyse'
    DEFAULT_CANDLE = '15m'

    def initialize(symbol, candle: DEFAULT_CANDLE, exchange: :nse, segment: :index, expiry: nil, trade_type: :analysis)
      @symbol   = symbol.to_s.upcase
      @candle   = candle
      @segment  = segment
      @exchange = exchange
      @expiry_override = expiry
      @trade_type = trade_type
    end

    class << self
      def call(*args, **kw) = new(*args, **kw).call
    end

    def call
      return log_missing unless instrument

      candle_series = instrument.candle_series(interval: @candle.delete_suffix('m'))
      md = build_market_snapshot(candle_series)

      sleep(1.5)
      md[:vix] = india_vix.ltp

      prompt = PromptBuilder.build_prompt(md, trade_type: @trade_type)
      Rails.logger.debug prompt
      push_info(md)
      answer = ask_openai(prompt)
      typing_ping

      Rails.logger.debug answer.length
      # TelegramNotifier.send_message(answer)
      # nil if answer
      answer
    rescue StandardError => e
      Rails.logger.error "[AnalysisService] ❌ #{e.class} – #{e.message}"
      nil
    end

    private

    def instrument
      @instrument ||= begin
        scope = Instrument.where(exchange: @exchange, segment: @segment)
        scope.find_by(underlying_symbol: @symbol)  ||
          scope.find_by(symbol_name:      @symbol) ||
          scope.find_by(trading_symbol:   @symbol)
      end
    end

    def india_vix
      @india_vix ||= Instrument.find_by(security_id: 21)
    end

    def build_market_snapshot(series)
      prev_day = previous_daily_ohlc

      ActiveSupport::HashWithIndifferentAccess.new(
        {
          symbol: instrument.symbol_name,
          ts: Time.current,
          frame: @candle,
          expiry: @expiry_override || nearest_expiry,
          ltp: series.closes.last,
          session: session_state,
          ohlc: {
            open: session_state == :live ? PriceMath.round_tick(series.opens.last) : PriceMath.round_tick(series.opens.second_to_last),
            high: session_state == :live ? PriceMath.round_tick(series.highs.last) : PriceMath.round_tick(series.highs.second_to_last),
            low: session_state == :live ? PriceMath.round_tick(series.lows.last) : PriceMath.round_tick(series.lows.second_to_last),
            close: session_state == :live ? PriceMath.round_tick(series.closes.last) : PriceMath.round_tick(series.closes.second_to_last),
            volume: series.candles.last.volume
          },
          prev_day: prev_day,
          boll: series.bollinger_bands(period: 20),
          atr: series.atr[:atr].round(2),
          rsi: series.rsi[:rsi].round(2),
          macd: series.macd.transform_values { |v| v.round(2) },
          ema14: series.moving_average(14)[:ema].round(2),
          super: series.supertrend_signal,
          hi20: series.recent_highs(20)[:highs].max.round(2),
          lo20: series.recent_lows(20)[:lows].min.round(2),
          liq_up: series.liquidity_grab_up?(lookback: 20)[:liquidity_grab_up],
          liq_dn: series.liquidity_grab_down?(lookback: 20)[:liquidity_grab_down],
          options: option_chain_analysis
        }
      )
    end

    # ------------------------------------------------------------------------
    # Option-chain preprocessing (unchanged logic moved to its own method)
    # ------------------------------------------------------------------------
    def option_chain_analysis
      raw = safe { instrument.fetch_option_chain(@expiry_override || nearest_expiry) }
      return nil unless raw

      Market::OptionChainAnalyzer
        .new(raw, instrument.ltp.to_f)
        .extract_data
    end

    def previous_daily_ohlc
      Rails.cache.fetch("pd-ohlc:#{instrument.id}", expires_in: 15.minutes) do
        to_date = MarketCalendar.today_or_last_trading_day
        from_date = MarketCalendar.last_trading_day(from: to_date - 1)
        bars = instrument.historical_ohlc(
          from_date: from_date.to_s,
          to_date: to_date.to_s
        )

        return nil if bars.blank?

        bar = bars
        {
          open: PriceMath.round_tick(bar['open'].last.to_f),
          high: PriceMath.round_tick(bar['high'].last.to_f),
          low: PriceMath.round_tick(bar['low'].last.to_f),
          close: PriceMath.round_tick(bar['close'].last.to_f)
        }
      end
    end

    def session_state
      now = Time.zone.now
      weekday = now.wday

      return :weekend if [0, 6].include?(weekday) # Sunday or Saturday

      case @exchange.to_sym
      when :nse, :bse
        return :pre_open   if now <  now.change(hour: 9, min: 15)
        return :post_close if now >= now.change(hour: 15, min: 30)
      when :mcx
        return :pre_open   if now <  now.change(hour: 9, min: 0)
        return :post_close if now >= now.change(hour: 23, min: 0)
      end

      :live
    end

    def push_info(md)
      options_text = format_options_chain(md[:options])
      weekend_note = md[:session] == :weekend ? ' (Weekend - Markets Closed)' : ''

      message = <<~TG
        #{TELEGRAM_TAG} – *#{md[:symbol]}*
        LTP  : ₹#{PriceMath.round_tick(md[:ltp])}
        Time : #{md[:ts].strftime('%H:%M:%S')}#{weekend_note}
        Frame: #{@candle}
        Exp  : #{md[:expiry]}
        ───────────────────────────
        #{options_text}
      TG

      TelegramNotifier.send_message(message)
    end

    def ask_openai(prompt, retries: 3, backoff: 4)
      attempt = 0

      begin
        Openai::ChatRouter.ask!(
          prompt,
          system: 'You are an elite Indian derivatives strategist.'
        )
      rescue OpenAI::Error
        attempt += 1
        raise if attempt > retries

        sleep backoff * attempt
        retry
      end
    end

    def format_options_chain(options)
      return 'No option-chain data available.' if options.blank?

      blocks = []

      {
        atm: 'ATM',
        otm_call: 'OTM CALL',
        itm_call: 'ITM CALL',
        otm_put: 'OTM PUT',
        itm_put: 'ITM PUT'
      }.each do |key, label|
        opt = options[key]
        next unless opt

        strike = opt[:strike] || '?'
        ce = opt[:call] || {}
        pe = opt[:put] || {}

        ce_ltp = opt[:ce_ltp] || ce['last_price'] || ce[:last_price]
        ce_iv = opt[:ce_iv] || ce['implied_volatility'] || ce[:implied_volatility]
        ce_oi = opt[:ce_oi] || ce['oi'] || ce[:oi]
        ce_delta = opt[:ce_delta] || dig_any(ce, 'greeks', 'delta')
        ce_theta = opt[:ce_theta] || dig_any(ce, 'greeks', 'theta')
        ce_gamma = opt[:ce_gamma] || dig_any(ce, 'greeks', 'gamma')
        ce_vega = opt[:ce_vega] || dig_any(ce, 'greeks', 'vega')

        pe_ltp = opt[:pe_ltp] || pe['last_price'] || pe[:last_price]
        pe_iv = opt[:pe_iv] || pe['implied_volatility'] || pe[:implied_volatility]
        pe_oi = opt[:pe_oi] || pe['oi'] || pe[:oi]
        pe_delta = opt[:pe_delta] || dig_any(pe, 'greeks', 'delta')
        pe_theta = opt[:pe_theta] || dig_any(pe, 'greeks', 'theta')
        pe_gamma = opt[:pe_gamma] || dig_any(pe, 'greeks', 'gamma')
        pe_vega = opt[:pe_vega] || dig_any(pe, 'greeks', 'vega')

        blocks << <<~STR.strip
          ► #{label} (#{strike})
            CALL: LTP ₹#{fmt2(ce_ltp)}  IV #{fmt2(ce_iv)}%  OI #{fmt2(ce_oi)}  Δ #{fmt2(ce_delta)}  Γ #{fmt2(ce_gamma)}  ν #{fmt2(ce_vega)}  θ #{fmt2(ce_theta)}
            PUT : LTP ₹#{fmt2(pe_ltp)}  IV #{fmt2(pe_iv)}%  OI #{fmt2(pe_oi)}  Δ #{fmt2(pe_delta)}  Γ #{fmt2(pe_gamma)}  ν #{fmt2(pe_vega)}  θ #{fmt2(pe_theta)}
        STR
      end

      blocks.join("\n\n")
    end

    def nearest_expiry
      raw = safe { instrument.expiry_list } || []
      raw.first
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.warn "[AnalysisService] ⚠️ #{e.class} – #{e.message}"
      nil
    end

    def log_missing
      Rails.logger.error "[AnalysisService] ⚠️ Instrument not found: #{@symbol}"
      nil
    end

    def fmt2(x)
      x.nil? ? '–' : x.to_f.round(2)
    end

    def dig_any(h, *path)
      h.is_a?(Hash) ? h.dig(*path) : nil
    end
  end
end
