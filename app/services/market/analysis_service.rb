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
      @instrument = locate_instrument

      unless @instrument
        Rails.logger.error "[AnalysisService] ⚠️ Instrument not found: #{@symbol}"
        return
      end

      md = pull_market_data

      return unless md

      prompt = build_prompt(md)
      pp prompt
      answer = ask_openai(prompt)
      # answer = prompt

      push_telegram(answer, md)

      answer # optional return for console / tests
    rescue StandardError => e
      Rails.logger.error "[AnalysisService] ❌ #{e.class} – #{e.message}"
      nil
    end

    # ========================================================================
    private

    # ========================================================================

    # ------------------------------------------------------------
    # 0️⃣  Resolve instrument row from DB
    # ------------------------------------------------------------
    def locate_instrument
      scope = Instrument.where(exchange: @exchange, segment: @segment)
      scope.find_by(underlying_symbol: @symbol)  ||
        scope.find_by(symbol_name:      @symbol) ||
        scope.find_by(trading_symbol:   @symbol)
    end

    # ------------------------------------------------------------
    # 1️⃣  Market-data fetch  (3-tier hierarchy + “close-as-ltp” fallback)
    # ------------------------------------------------------------
    def pull_market_data
      # ── Tier-1 ─────────────────────────────────────────────────
      ltp  = safe { @instrument.ltp }
      ohlc = safe_ohlc_from_instrument

      # ── Tier-2  (historical helpers) ──────────────────────────
      ohlc = safe_ohlc_from_historical if ohlc.blank?
      # ── Tier-3  (raw REST) ────────────────────────────────────
      # ltp, ohlc = safe_rest_fallback if ltp.blank? || ohlc.blank?

      # ── “close → ltp” safety-net  (handles weekend / offline hours)
      if ltp.blank? && ohlc.present?
        ltp = ohlc[:close].last || ohlc['close'].last
        Rails.logger.debug '[AnalysisService] ℹ️   LTP missing – using last close'
      end

      return if ltp.blank? || ohlc.blank?

      option_chain_raw = safe { @instrument.fetch_option_chain(@expiry_override || nearest_expiry) }
      options_data = nil

      if option_chain_raw.present?
        analyzer = Market::OptionChainAnalyzer.new(
          option_chain_raw,
          ltp.to_f
        )
        options_data = analyzer.extract_data
      end

      {
        symbol: @instrument.symbol_name,
        ltp: ltp.to_f,
        open: (ohlc[:open]&.last   || ohlc['open']&.last)&.to_f,
        high: (ohlc[:high]&.last   || ohlc['high']&.last)&.to_f,
        low: (ohlc[:low]&.last || ohlc['low']&.last)&.to_f,
        close: (ohlc[:close]&.last || ohlc['close']&.last)&.to_f,
        volume: (ohlc[:volume]&.last || ohlc['volume']&.last).to_i,
        ts: Time.current,
        expiry: @expiry_override || nearest_expiry,
        options: options_data
      }
    end

    # helper – fetch via Instrument#ohlc if signature matches
    def safe_ohlc_from_instrument
      sleep(1.1)
      meth = @instrument.method(:ohlc)
      arity = meth.arity
      ohlc = safe { arity.zero? ? meth.call : meth.call(@candle, limit: 1) }['ohlc']
      { 'open' => [ohlc['open']], 'close' => [ohlc['close']], 'high' => [ohlc['high']], 'low' => [ohlc['low']] }
    end

    # helper – use new historical helpers the model exposes
    def safe_ohlc_from_historical
      if @candle.match?(/m\z/i)                 # minutes → intraday
        interval = @candle.delete_suffix('m')
        arr = safe { @instrument.intraday_ohlc(interval: interval) }
      else                                      # anything else → daily
        arr = safe { @instrument.historical_ohlc }
      end
      arr # both helpers return an *array* of bars
    end

    # helper – raw MarketFeed tier
    def safe_rest_fallback
      seg = @instrument.exchange_segment
      sid = @instrument.security_id

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

    # ------------------------------------------------------------
    # 2️⃣  Prompt builder
    # ------------------------------------------------------------
    def build_prompt(md)
      <<~PROMPT
        🔮 You are an expert financial analyst specialising in Indian equity
        & derivatives markets, focused on buying **#{md[:symbol]}** options.

        Current Spot Price: **₹#{md[:ltp]}**

        Technicals:
        • Open: ₹#{md[:open]}
        • High: ₹#{md[:high]}
        • Low: ₹#{md[:low]}
        • Close: ₹#{md[:close]}
        • Volume: #{md[:volume]}

        Options Chain Data:
        #{format_options_chain(md[:options])}

        Analyse:
        • Technicals (candlesticks, S/R, volatility, Greeks)
        • Fundamentals (FII/DII flows, macro news, RBI commentary)
        • OI & IV trends
        • Greeks (delta, theta, vega, gamma)
        • Intraday bias
        • Recommend whether to buy Calls, Puts or Straddle/Strangle
        • Suggest strike prices for expiry #{md[:expiry]}
        Produce intraday probabilities (%) for:
        • Probability of ≥ 30-50% intraday profit
        • Key risks
        – Significant upside – Significant downside – Flat market

        From **#{md[:ltp]}**, estimate whether #{md[:symbol]} closes higher,
        lower, or flat *today* and state your key assumptions.

        Then recommend the best intraday #{md[:symbol]} options-buying strategy:
        – Buy calls – Buy puts – Both (straddle / strangle)
        Provide a concise trading plan with:
        • Strikes to buy
        • Stop-loss
        • Target
        For each idea:
        • Suggest strike(s) for expiry **#{md[:expiry]}**
        • Premium range in ₹
        • Probability of ≥ 30-50 % intraday profit
        • Key risks

        Finish with a concise actionable summary:
        – Exact strike(s) to buy
        – Suggested stop-loss & target.
      PROMPT
    end

    def format_options_chain(data)
      return 'No option chain data available.' unless data

      blocks = %i[atm otm_call itm_call otm_put itm_put].map do |k|
        opt = data[k]
        next unless opt

        <<~STR
          ► #{k.to_s.upcase}
          Strike: #{opt[:strike]}
          CALL:
            LTP: ₹#{opt[:call]['last_price']}
            IV: #{opt[:call]['implied_volatility']}
            OI: #{opt[:call]['oi']}
            Delta: #{opt[:call].dig('greeks', 'delta')}
          PUT:
            LTP: ₹#{opt[:put]['last_price']}
            IV: #{opt[:put]['implied_volatility']}
            OI: #{opt[:put]['oi']}
            Delta: #{opt[:put].dig('greeks', 'delta')}
        STR
      end

      blocks.compact.join("\n\n")
    end

    # ----------------------------------------------------------------
    # 3️⃣  OpenAI call  (auto-retry on 429 / rate-limit)
    # ----------------------------------------------------------------
    def ask_openai(prompt, retries: 3, backoff: 4)
      attempt = 0

      begin
        Openai::ChatRouter.ask!(               # ← use your central router
          prompt,
          system: 'You are an elite Indian derivatives strategist.',
          temperature: 0.4                     # keep previous settings
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
        ───────────────────────────
        #{text}
      TG

      TelegramNotifier.send_message(message)
    end

    # ------------------------------------------------------------
    # utility helpers
    # ------------------------------------------------------------
    def nearest_expiry
      raw = safe { @instrument.expiry_list } || []
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
  end
end
