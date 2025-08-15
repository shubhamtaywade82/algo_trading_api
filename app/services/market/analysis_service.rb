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
    DEFAULT_CANDLE = '5m'

    # ─────────────────────────────────────────────────────────────
    # constructor (only *symbol* is strictly required)
    # ─────────────────────────────────────────────────────────────
    def initialize(symbol,
                   candle: DEFAULT_CANDLE,
                   exchange: :nse,
                   segment: :index,
                   expiry: nil)
      @symbol   = symbol.to_s.upcase     # “NIFTY”
      @candle   = candle                 # “1D”, “5m”, …
      @segment  = segment                # :index / :equity / :derivatives
      @exchange = exchange               # :nse (default)
      @expiry_override = expiry
    end

    # convenience wrapper → keeps old `.call` API intact
    class << self
      def call(*args, **kw) = new(*args, **kw).call
    end

    # ========================================================================
    # main entry
    # ========================================================================
    def call
      return log_missing unless instrument

      candle_series = instrument.candle_series(interval: @candle.delete_suffix('m'))
      md = build_market_snapshot(candle_series)

      sleep(1.5) # give the DB a breather
      md[:vix] = india_vix.ltp

      # prompt = build_prompt(md)
      prompt = PromptBuilder.build_prompt(md) # , context: 'Prefer 0.35–0.55 delta; if IV percentile > 70, avoid fresh straddles.')
      Rails.logger.debug prompt
      answer = ask_openai(prompt)
      # answer = prompt

      push_telegram(answer, md)

      nil if answer # optional return for console / tests
    rescue StandardError => e
      Rails.logger.error "[AnalysisService] ❌ #{e.class} – #{e.message}"
      nil
    end

    # ========================================================================
    # private

    # ========================================================================

    # ------------------------------------------------------------
    # 0️⃣  Resolve instrument row from DB
    # ------------------------------------------------------------
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

    # # ------------------------------------------------------------
    # # 1️⃣  Market-data fetch  (3-tier hierarchy + “close-as-ltp” fallback)
    # # ------------------------------------------------------------
    # def pull_market_data
    #   # ── Tier-1 ─────────────────────────────────────────────────
    #   ltp  = safe { instrument.ltp }
    #   ohlc = safe_ohlc_from_instrument

    #   # ── Tier-2  (historical helpers) ──────────────────────────
    #   ohlc = safe_ohlc_from_historical if ohlc.blank?
    #   # ── Tier-3  (raw REST) ────────────────────────────────────
    #   # ltp, ohlc = safe_rest_fallback if ltp.blank? || ohlc.blank?

    #   # ── “close → ltp” safety-net  (handles weekend / offline hours)
    #   if ltp.blank? && ohlc.present?
    #     ltp = ohlc[:close].last || ohlc['close'].last
    #     Rails.logger.debug '[AnalysisService] ℹ️   LTP missing – using last close'
    #   end

    #   return if ltp.blank? || ohlc.blank?

    #   option_chain_raw = safe { instrument.fetch_option_chain(@expiry_override || nearest_expiry) }
    #   options_data = nil

    #   if option_chain_raw.present?
    #     analyzer = Market::OptionChainAnalyzer.new(
    #       option_chain_raw,
    #       ltp.to_f
    #     )
    #     options_data = analyzer.extract_data
    #   end

    #   {
    #     symbol: instrument.symbol_name,
    #     ltp: ltp.to_f,
    #     open: (ohlc[:open]&.last   || ohlc['open']&.last)&.to_f,
    #     high: (ohlc[:high]&.last   || ohlc['high']&.last)&.to_f,
    #     low: (ohlc[:low]&.last || ohlc['low']&.last)&.to_f,
    #     close: (ohlc[:close]&.last || ohlc['close']&.last)&.to_f,
    #     volume: (ohlc[:volume]&.last || ohlc['volume']&.last).to_i,
    #     ts: Time.current,
    #     expiry: @expiry_override || nearest_expiry,
    #     options: options_data
    #   }
    # end

    # ------------------------------------------------------------------------
    # Build a rich hash of market data + indicators for the prompt
    # ------------------------------------------------------------------------
    def build_market_snapshot(series)
      prev_day = previous_daily_ohlc

      ActiveSupport::HashWithIndifferentAccess.new(
        {
          symbol: instrument.symbol_name,
          ts: Time.current,
          frame: @candle,
          expiry: @expiry_override || nearest_expiry,
          ltp: series.closes.last,

          # latest intraday bar
          ohlc: {
            open: session_state == :live ? series.opens.last.round(2) : series.opens.second_to_last.round(2),
            high: session_state == :live ? series.highs.last.round(2) : series.highs.second_to_last.round(2),
            low: session_state == :live ? series.lows.last.round(2) : series.lows.second_to_last.round(2),
            close: session_state == :live ? series.closes.last.round(2) : series.closes.second_to_last.round(2),
            volume: series.candles.last.volume
          },

          # previous daily bar
          prev_day: prev_day,

          # indicators
          boll: series.bollinger_bands(period: 20),                # {upper, middle, lower}
          atr: series.atr[:atr].round(2),
          rsi: series.rsi[:rsi].round(2),
          macd: series.macd.transform_values { |v| v.round(2) },   # {macd, signal, hist}
          ema14: series.moving_average(14)[:ema].round(2), # (ADX placeholder)
          super: series.supertrend_signal, # (period: 10, multiplier: 3),      # {line, signal}

          # price-action context
          hi20: series.recent_highs(20)[:highs].max.round(2),
          lo20: series.recent_lows(20)[:lows].min.round(2),
          liq_up: series.liquidity_grab_up?(lookback: 20)[:liquidity_grab_up],
          liq_dn: series.liquidity_grab_down?(lookback: 20)[:liquidity_grab_down],

          # option-chain
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

    # helper – fetch via Instrument#ohlc if signature matches
    def safe_ohlc_from_instrument
      sleep(1.1)
      meth = instrument.method(:ohlc)
      arity = meth.arity
      ohlc = safe { arity.zero? ? meth.call : meth.call(@candle, limit: 1) }['ohlc']
      { 'open' => [ohlc['open']], 'close' => [ohlc['close']], 'high' => [ohlc['high']], 'low' => [ohlc['low']] }
    end

    # helper – use new historical helpers the model exposes
    def safe_ohlc_from_historical
      if @candle.match?(/m\z/i)                 # minutes → intraday
        interval = @candle.delete_suffix('m')
        arr = safe { instrument.intraday_ohlc(interval: interval) }
      else                                      # anything else → daily
        arr = safe { instrument.historical_ohlc }
      end
      arr # both helpers return an *array* of bars
    end

    # helper – raw MarketFeed tier
    def safe_rest_fallback
      seg = instrument.exchange_segment
      sid = instrument.security_id

      ltp = safe do
        Dhanhq::API::MarketFeed
          .ltp({ seg => [sid] })
          .dig('data', seg, sid.to_s, 'lastPrice')
      end

      ohlc = safe do
        Dhanhq::API::MarketFeed
          .ohlc({ seg => [sid] })
          .dig('data', seg, sid.to_s)
      end

      [ltp, ohlc]
    end

    # ────────────────────────────────────────────────────────────── Helpers
    def previous_daily_ohlc
      Rails.cache.fetch("pd-ohlc:#{instrument.id}", expires_in: 15.minutes) do
        to_date = MarketCalendar.today_or_last_trading_day
        from_date = MarketCalendar.last_trading_day(from: to_date - 1)
        bars = instrument.historical_ohlc(
          from_date: from_date.to_s,
          to_date: to_date.to_s
        )

        next nil if bars.blank?

        bar = bars
        { open: bar['open'].last.to_f.round(2),
          high: bar['high'].last.to_f.round(2),
          low: bar['low'].last.to_f.round(2),
          close: bar['close'].last.to_f.round(2) }
      end
    end

    def session_state
      now = Time.zone.now
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

    def session_label
      { pre_open: '⏰ *Pre-open* session',
        live: '🟢 *Live* session',
        post_close: '🔒 *Post-close* session' }[session_state]
    end

    def nearest_expiry
      raw = safe { @instrument.expiry_list } || []
      raw.first
    end

    def build_prompt(md)
      pd = md[:prev_day] # previous-day OHLC hash or nil
      b = md[:boll] # Bollinger hash

      # Human-friendly phrasing for the session
      task_context =
        case session_state
        when :pre_open   then 'for the upcoming open'
        when :post_close then 'for tomorrow'
        else                  'right now during live trading'
        end

      <<~PROMPT
        #{session_label} – **#{md[:symbol]}**

        *Previous day* O #{pd&.dig(:open) || '–'} H #{pd&.dig(:high) || '–'} L #{pd&.dig(:low) || '–'} C #{pd&.dig(:close) || '–'}
        *Current #{md[:frame]}* O #{md[:ohlc][:open]} H #{md[:ohlc][:high]} L #{md[:ohlc][:low]} C #{md[:ohlc][:close]} Vol #{md[:ohlc][:volume]}

        ATR-14 #{md[:atr]} | RSI-14 #{md[:rsi]}
        Bollinger U #{b[:upper].round(1)}, M #{b[:middle].round(1)}, L #{b[:lower].round(1)}
        MACD L #{md[:macd][:macd]} S #{md[:macd][:signal]} H #{md[:macd][:hist]}
        Super-Trend #{md[:super] || 'neutral'}
        20-bar range H #{md[:hi20]} / L #{md[:lo20]}
        Liquidity grabs ↑ #{md[:liq_up]} ↓ #{md[:liq_dn]}

        *Options-chain snapshot* (expiry #{md[:expiry]}):
        #{format_options_chain(md[:options])}

        **TASK** – #{session_state == :live ? 'Intraday plan' : 'Preparation'}
        1. Analyse **technicals** (candlesticks, S/R, volatility bands, above metrics) #{task_context}.
        2. Summarise **fundamentals & flows** (FII/DII, macro news, RBI commentary).
        3. Evaluate **OI & IV trends** and **Greeks** (delta, theta, vega, gamma).
        4. Provide **ONE primary** & **ONE hedge** idea:
           • Strike(s) (liquid lots) • Entry premium (₹) • SL • T1 & T2 • Probabilities ≥30 %, ≥50 %, ≥70 %.
        5. Justify CE vs PE vs combo using ATR compression/expansion, Bollinger position, MACD momentum, RSI extremes, Super-Trend bias and liquidity-grab context.
        6. End with ≤4 concise bullets – exact action plan (strikes, SL, targets).

      PROMPT
    end

    # # ------------------------------------------------------------
    # # 2️⃣  Prompt builder
    # # ------------------------------------------------------------
    # def build_prompt(md)
    #   <<~PROMPT
    #     🔮 You are an expert financial analyst specialising in Indian equity
    #     & derivatives markets, focused on buying **#{md[:symbol]}** options.

    #     Current Spot Price: **₹#{md[:ltp]}**

    #     Technicals:
    #     • Open: ₹#{md[:open]}
    #     • High: ₹#{md[:high]}
    #     • Low: ₹#{md[:low]}
    #     • Close: ₹#{md[:close]}
    #     • Volume: #{md[:volume]}

    #     Options Chain Data:
    #     #{format_options_chain(md[:options])}

    #     Analyse:
    #     • Technicals (candlesticks, S/R, volatility, Greeks)
    #     • Fundamentals (FII/DII flows, macro news, RBI commentary)
    #     • OI & IV trends
    #     • Greeks (delta, theta, vega, gamma)
    #     • Intraday bias
    #     • Recommend whether to buy Calls, Puts or Straddle/Strangle
    #     • Suggest strike prices for expiry #{md[:expiry]}
    #     Produce intraday probabilities (%) for:
    #     • Probability of ≥ 30-50% intraday profit
    #     • Key risks
    #     – Significant upside – Significant downside – Flat market

    #     From **#{md[:ltp]}**, estimate whether #{md[:symbol]} closes higher,
    #     lower, or flat *today* and state your key assumptions.

    #     Then recommend the best intraday #{md[:symbol]} options-buying strategy:
    #     – Buy calls – Buy puts – Both (straddle / strangle)
    #     Provide a concise trading plan with:
    #     • Strikes to buy
    #     • Stop-loss
    #     • Target
    #     For each idea:
    #     • Suggest strike(s) for expiry **#{md[:expiry]}**
    #     • Premium range in ₹
    #     • Probability of ≥ 30-50 % intraday profit
    #     • Key risks

    #     Finish with a concise actionable summary:
    #     – Exact strike(s) to buy
    #     – Suggested stop-loss & target.
    #   PROMPT
    # end
    # Expanded to include OI, Gamma, Vega for both CE & PE and accept both shapes
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
        ce     = opt[:call] || {}
        pe     = opt[:put]  || {}

        # Support flattened fields too:
        ce_ltp   = opt[:ce_ltp] || ce['last_price'] || ce[:last_price]
        ce_iv    = opt[:ce_iv]  || ce['implied_volatility'] || ce[:implied_volatility]
        ce_oi    = opt[:ce_oi]  || ce['oi'] || ce[:oi]
        ce_delta = opt[:ce_delta] || dig_any(ce, 'greeks', 'delta')
        ce_theta = opt[:ce_theta] || dig_any(ce, 'greeks', 'theta')
        ce_gamma = opt[:ce_gamma] || dig_any(ce, 'greeks', 'gamma')
        ce_vega  = opt[:ce_vega]  || dig_any(ce, 'greeks', 'vega')

        pe_ltp   = opt[:pe_ltp] || pe['last_price'] || pe[:last_price]
        pe_iv    = opt[:pe_iv]  || pe['implied_volatility'] || pe[:implied_volatility]
        pe_oi    = opt[:pe_oi]  || pe['oi'] || pe[:oi]
        pe_delta = opt[:pe_delta] || dig_any(pe, 'greeks', 'delta')
        pe_theta = opt[:pe_theta] || dig_any(pe, 'greeks', 'theta')
        pe_gamma = opt[:pe_gamma] || dig_any(pe, 'greeks', 'gamma')
        pe_vega  = opt[:pe_vega]  || dig_any(pe, 'greeks', 'vega')

        blocks << <<~STR.strip
          ► #{label} (#{strike})
            CALL: LTP ₹#{ce_ltp.round(2) || '–'}  IV #{ce_iv.round(2) || '–'}%  OI #{ce_oi.round(2) || '–'}  Δ #{ce_delta.round(2) || '–'}  Γ #{ce_gamma.round(2) || '–'}  ν #{ce_vega.round(2) || '–'}  θ #{ce_theta.round(2) || '–'}
            PUT : LTP ₹#{pe_ltp.round(2) || '–'}  IV #{pe_iv.round(2) || '–'}%  OI #{pe_oi.round(2) || '–'}  Δ #{pe_delta.round(2) || '–'}  Γ #{pe_gamma.round(2) || '–'}  ν #{pe_vega.round(2) || '–'}  θ #{pe_theta.round(2) || '–'}
        STR
      end

      blocks.join("\n\n")
    end
    # def format_options_chain(data)
    #   return 'No option chain data available.' unless data

    #   blocks = %i[atm otm_call itm_call otm_put itm_put].map do |k|
    #     opt = data[k]
    #     next unless opt

    #     <<~STR
    #       ► #{k.to_s.upcase} (#{opt[:strike]})
    #       CE:
    #         LTP: ₹#{opt[:call]['last_price'].round(2)} IV: #{opt[:call]['implied_volatility'].round(2)} OI: #{opt[:call]['oi'].round(2)} Delta: #{opt[:call].dig('greeks', 'delta').round(2)}
    #         Theta: #{opt[:call].dig('greeks', 'theta').round(2)} Gamma: #{opt[:call].dig('greeks', 'gamma').round(2)} Vega: #{opt[:call].dig('greeks', 'vega').round(2)}
    #       PE:
    #         LTP: ₹#{opt[:put]['last_price'].round(2)} IV: #{opt[:put]['implied_volatility'].round(2)} OI: #{opt[:put]['oi'].round(2)} Delta: #{opt[:put].dig('greeks', 'delta').round(2)}
    #         Theta: #{opt[:put].dig('greeks', 'theta').round(2)} Gamma: #{opt[:put].dig('greeks', 'gamma').round(2)} Vega: #{opt[:put].dig('greeks', 'vega').round(2)}
    #       ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
    #     STR
    #   end

    #   blocks.compact.join("\n")
    # end

    # ----------------------------------------------------------------
    # 3️⃣  OpenAI call  (auto-retry on 429 / rate-limit)
    # ----------------------------------------------------------------
    def ask_openai(prompt, retries: 3, backoff: 4)
      attempt = 0

      begin
        Openai::ChatRouter.ask!( # ← use your central router
          prompt,
          system: 'You are an elite Indian derivatives strategist.'
        )
      rescue OpenAI::Error::RateLimitError
        attempt += 1
        raise if attempt > retries

        sleep backoff * attempt # simple exponential back-off
        retry
      end
    end

    # ------------------------------------------------------------
    # 4️⃣  Telegram
    # ------------------------------------------------------------
    def push_telegram(text, md)
      options_text = format_options_chain(md[:options])

      message = <<~TG
        #{TELEGRAM_TAG} – *#{md[:symbol]}*
        LTP  : ₹#{md[:ltp].round(2)}
        Time : #{md[:ts].strftime('%H:%M:%S')}
        Frame: #{@candle}
        Exp  : #{md[:expiry]}
        ───────────────────────────
        #{options_text}
      TG
      TelegramNotifier.send_message(message)
      TelegramNotifier.send_message(text)
    end

    # ------------------------------------------------------------
    # utility helpers
    # ------------------------------------------------------------
    def nearest_expiry
      raw = safe { instrument.expiry_list } || []
      raw.empty? ? [] : raw.first
    end

    def escape_markdown_v2(text)
      text.gsub(/([_*\[\]()~`>#+\-=|{}.!\\])/, '\\\\\1')
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

    def dig_any(h, *path)
      h.is_a?(Hash) ? h.dig(*path) : nil
    end
  end
end
