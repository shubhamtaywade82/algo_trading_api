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
      return nil if candle_series.candles.blank?

      md = build_market_snapshot(candle_series)

      sleep(1.5)
      md[:vix] = india_vix&.ltp
      md[:regime] = option_chain_regime_flags(md[:options], md[:vix])

      prompt = PromptBuilder.build_prompt(md, trade_type: @trade_type)
      Rails.logger.debug prompt
      push_info(md)
      answer = ask_openai(prompt)
      typing_ping

      answer = normalize_response(answer, md) if answer.present?
      Rails.logger.debug answer.length
      answer
    rescue StandardError => e
      Rails.logger.error "[AnalysisService] ❌ #{e.class} – #{e.message}"
      Rails.logger.error e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
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
            volume: series.candles.last&.volume.to_f
          },
          prev_day: prev_day,
          boll: series.bollinger_bands(period: 20),
          atr: round_or_nil(series.atr[:atr]),
          rsi: round_or_nil(series.rsi[:rsi]),
          macd: series.macd.transform_values { |v| round_or_nil(v) },
          ema14: round_or_nil(series.moving_average(14)[:ema]),
          super: series.supertrend_signal,
          hi20: round_or_nil(series.recent_highs(20)[:highs].max),
          lo20: round_or_nil(series.recent_lows(20)[:lows].min),
          liq_up: series.liquidity_grab_up?(lookback: 20)[:liquidity_grab_up],
          liq_dn: series.liquidity_grab_down?(lookback: 20)[:liquidity_grab_down],
          **smc_and_price_action(series),
          options: option_chain_analysis
        }
      )
    end

    def smc_and_price_action(series)
      Market::SmcPriceActionAnalyzer.new(series).call
    rescue StandardError => e
      Rails.logger.warn { "[AnalysisService] SMC/price-action failed – #{e.message}" }
      { smc: {}, price_action: {} }
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
        today = Time.zone.today
        to_date = (defined?(MarketCalendar) && MarketCalendar.respond_to?(:today_or_last_trading_day) ? MarketCalendar.today_or_last_trading_day : today) || today
        from_date = safe_from_date_for_prev_ohlc(to_date)
        from_date = fallback_from_date(to_date) if from_date.blank?
        bars = instrument.historical_ohlc(
          from_date: from_date.to_s,
          to_date: to_date.to_s
        )

        return nil if bars.blank? || !valid_daily_ohlc_bars?(bars)

        {
          open: PriceMath.round_tick(bars['open'].last.to_f),
          high: PriceMath.round_tick(bars['high'].last.to_f),
          low: PriceMath.round_tick(bars['low'].last.to_f),
          close: PriceMath.round_tick(bars['close'].last.to_f)
        }
      end
    end

    def safe_from_date_for_prev_ohlc(to_date)
      ref = to_date.presence || Time.zone.today
      return Time.zone.today - 2 if ref.nil?
      return (ref - 2) unless defined?(MarketCalendar) && MarketCalendar.respond_to?(:from_date_for_last_n_trading_days)

      MarketCalendar.from_date_for_last_n_trading_days(ref, 2)
    end

    def fallback_from_date(to_date)
      return Time.zone.today - 2 if to_date.nil? || !to_date.respond_to?(:-)

      to_date - 2
    end

    def valid_daily_ohlc_bars?(bars)
      %w[open high low close].all? { |k| bars[k].is_a?(Array) && bars[k].present? }
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
      options_text = format_options_at_a_glance(md[:options])
      weekend_note = md[:session] == :weekend ? ' (Weekend - Markets Closed)' : ''

      message = <<~TG
        #{TELEGRAM_TAG} – *#{md[:symbol]}*
        LTP ₹#{PriceMath.round_tick(md[:ltp])} · #{md[:ts].strftime('%H:%M')}#{weekend_note} · #{@candle} · Exp #{md[:expiry]}
        _#{Openai::ChatRouter.backend_label}_
        ───────────────────────────
        #{options_text}
      TG

      TelegramNotifier.send_message(message)
    end

    def normalize_response(answer, md)
      Market::AnalysisResponseNormalizer.new(answer, md).call
    end

    def ask_openai(prompt, retries: 3, backoff: 4)
      attempt = 0

      begin
        Openai::ChatRouter.ask!(
          prompt,
          system: Market::PromptBuilder.system_prompt(@trade_type)
        )
      rescue OpenAI::Error
        attempt += 1
        raise if attempt > retries

        sleep backoff * attempt
        retry
      end
    end

    # Snapshot for Telegram: ATM + ATM+1 (OTM CALL) + ATM−1 (OTM PUT strike) so the first message shows key strikes.
    def format_options_at_a_glance(options)
      return 'No option-chain data available.' if options.blank?

      blocks = []

      %i[atm otm_call otm_put].each do |key|
        opt = options[key]
        next unless opt

        label = case key
                when :atm then 'ATM'
                when :otm_call then 'OTM+1 (CALL)'
                when :otm_put then 'OTM−1 (PUT)'
                else key.to_s.titleize
                end

        blocks << format_one_strike_row(opt, label)
      end

      return 'No option-chain data available.' if blocks.empty?

      blocks.join("\n\n")
    end

    def format_one_strike_row(opt, label)
      strike = opt[:strike] || '?'
      ce = opt[:call] || {}
      pe = opt[:put] || {}

      ce_ltp = opt[:ce_ltp] || ce['last_price'] || ce[:last_price]
      ce_iv = opt[:ce_iv] || ce['implied_volatility'] || ce[:implied_volatility]
      ce_delta = opt[:ce_delta] || dig_any(ce, 'greeks', 'delta')
      ce_theta = opt[:ce_theta] || dig_any(ce, 'greeks', 'theta')

      pe_ltp = opt[:pe_ltp] || pe['last_price'] || pe[:last_price]
      pe_iv = opt[:pe_iv] || pe['implied_volatility'] || pe[:implied_volatility]
      pe_delta = opt[:pe_delta] || dig_any(pe, 'greeks', 'delta')
      pe_theta = opt[:pe_theta] || dig_any(pe, 'greeks', 'theta')

      <<~STR.strip
        #{label} #{strike}
        CE ₹#{fmt2(ce_ltp)}  IV #{fmt2(ce_iv)}%  Δ #{fmt2(ce_delta)}  θ #{fmt2(ce_theta)}
        PE ₹#{fmt2(pe_ltp)}  IV #{fmt2(pe_iv)}%  Δ #{fmt2(pe_delta)}  θ #{fmt2(pe_theta)}
      STR
    end

    # Full chain for prompts; kept for any consumer that needs all strikes.
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

    def option_chain_regime_flags(options, vix)
      return {} if options.blank?

      atm = options[:atm] || {}
      ce_iv = (atm[:ce_iv] || atm.dig(:call, 'implied_volatility')).to_f
      pe_iv = (atm[:pe_iv] || atm.dig(:put,  'implied_volatility')).to_f
      iv_atm = [ce_iv, pe_iv].reject(&:zero?).sum / 2.0

      {
        iv_atm: iv_atm,
        iv_high: iv_atm >= 18, # tune thresholds per index
        iv_low: iv_atm <= 10,
        vix: vix.to_f,
        vix_high: vix.to_f >= 16,
        vix_low: vix.to_f <= 11
      }
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

    def round_or_nil(value)
      value&.to_f&.round(2)
    end

    def fmt2(x)
      x.nil? ? '–' : x.to_f.round(2)
    end

    def dig_any(h, *path)
      h.is_a?(Hash) ? h.dig(*path) : nil
    end
  end
end
