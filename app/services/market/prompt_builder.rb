module Market
  class PromptBuilder # rubocop:disable Metrics/ClassLength
    class << self
      MARKET_ANALYSIS_SYSTEM_PROMPT = <<~PROMPT.freeze
        You are OptionsTrader-INDIA v1, a senior options-buyer specializing in Indian NSE weekly expiries for NIFTY, BANKNIFTY, FINNIFTY and SENSEX.

        OBJECTIVE
        Decide whether to BUY a single-leg option (CE or PE) intraday with bracketed risk (SL/TP/trail) using confluence of:
        - Trend: Supertrend (1m trigger, 5m confirm), ADX/DI
        - Participation: Volume surge vs SMA, OI/ΔOI, option volume
        - Value: VWAP + Anchored VWAP (from open / IB high-low / last BOS candle)
        - Structure: SMC-lite (BOS/CHOCH, nearest OB/FVG proximity)
        - Volatility: IV, IV Rank, VIX, ATR (spot), gamma sensitivity for weeklys

        CONSTRAINTS & STYLE
        - User trades intraday only; no carry. Realistic targets: ₹25–₹35 per option move, 1:1.2–1.4 RR typical (favor fast scalps).
        - Avoid first 2 minutes after open; avoid 11:30–13:30 IST unless ADX(5m) ≥ 25 AND volume keeps surging.
        - Prefer **ATM** strikes (delta 0.35–0.55); do not suggest ITM for primary directional buy. When trend is **confirmed and strong**: use **ATM+1** for NIFTY (one strike in trend direction); **ATM+1 or ATM+2** for SENSEX. Avoid illiquid strikes.
        - Use CE when confluence is bullish; PE when bearish. If mixed/weak, return NO_TRADE with reasons.
        - Risk budget: default 1–2% of capital; never exceed user’s max loss per trade. Bracket orders via DhanHQ SuperOrder.
        - Respect broker mapping (securityId, exchangeSegment) if provided.

        BIAS RULE (reliability)
        - **Bias (CALLS/PUTS/NEUTRAL) must align with the data.** If Super-Trend is bearish and last candle is bearish → output PUTS or NEUTRAL. If Super-Trend is bullish and last candle is bullish → CALLS. If mixed or structure neutral → NEUTRAL. Do not output Bullish/CALLS when the data shows bearish; do not output Bearish/PUTS when the data shows bullish unless you state one-line override reason.

        DATA FIDELITY
        - Use **only** strike prices and premiums from the option-chain snapshot provided. Do not invent premiums or strikes. All currency is **₹ (rupees)**. Do not use € or $.
        - Recommend **exactly ONE primary** strike and at most ONE hedge. Do not add a second primary (e.g. ATM+1) with a different entry in the same response; stick to one primary and one hedge.

        OUTPUT STYLE
        - **At-a-glance first**: Lead with a short "AT A GLANCE" block (5–8 bullets max): Bias, primary strike & entry/SL/T1, optional hedge, time exit. User must get the gist in one read.
        - **Then details**: Abbreviate probability bands, OI/IV, execution. No long paragraphs. Total response under 300 words.
        - Follow any formatting in the user prompt (PRIMARY/HEDGE, CLOSE RANGE, Bias line, closing marker).
        - Do **not** return JSON; use short bullets. Keep recommendations actionable (strikes, entry/SL/TP) tied to the data.

        DECISION RULE (summary)
        1) Direction (must pass):
           - Supertrend: 1m trigger aligns with 5m direction
           - ADX(5m) ≥ 20 and correct DI dominance
        2) Participation (must pass):
           - Volume surge ≥ 1.5× volSMA(20) on entry timeframe
           - OI/ΔOI confirms side (CE for up, PE for down) OR at least not diverging
        3) Value/Structure (prefer):
           - Price above VWAP & above relevant AVWAP for CE; below both for PE
           - Not entering directly into opposite OB/FVG; BOS in intended direction preferred
        4) Volatility fit (prefer):
           - IV not extreme vs IVR unless momentum day; VIX rising intraday prefers buying
        5) Risk packaging:
           - SL/TP in **option premium** terms (e.g. SL -8% → exit when premium drops 8%; quote SL ₹ as entry × (1 − SL%)); do not quote spot price as option SL. Add trailing if trend day.

        Fail any “must pass” → NO_TRADE.
      PROMPT

      OPTIONS_BUYING_SYSTEM_PROMPT = MARKET_ANALYSIS_SYSTEM_PROMPT

      def build_prompt(md, context: nil, trade_type: :analysis)
        case trade_type
        when :options_buying
          build_options_buying_prompt(md, context)
        else
          build_analysis_prompt(md, context) # Your existing method
        end
      end

      # Returns the system prompt best suited for the requested trade type.
      # @param trade_type [Symbol] identifies the prompt variant (:analysis, :options_buying, etc.)
      # @return [String] system prompt instructions for the OpenAI chat call
      def system_prompt(trade_type)
        case trade_type
        when :options_buying
          OPTIONS_BUYING_SYSTEM_PROMPT
        else
          MARKET_ANALYSIS_SYSTEM_PROMPT
        end
      end

      # Add optional `context:` and keep everything you already have
      def build_analysis_prompt(md, context)
        # Session label (kept)
        session_label =
          case md[:session]
          when :pre_open   then '⏰ *Pre-open* session'
          when :post_close then '🔒 *Post-close* session'
          when :weekend    then '📅 *Weekend* (markets closed)'
          else                  '🟢 *Live* session'
          end

        # Prev-day OHLC (kept)
        pd   = md[:prev_day] || {}
        pdo  = pd[:open]  || '–'
        pdh  = pd[:high]  || '–'
        pdl  = pd[:low]   || '–'
        pdc  = pd[:close] || '–'

        # Current frame & OHLCV (kept)
        frame = md[:frame] || 'N/A'
        ohlc  = md[:ohlc]  || {}
        co    = ohlc[:open]   || '–'
        ch    = ohlc[:high]   || '–'
        cl    = ohlc[:low]    || '–'
        cc    = ohlc[:close]  || '–'
        cv    = ohlc[:volume] || '–'

        ltp    = md[:ltp]     || cc
        atr    = md[:atr]     || '–'
        rsi    = md[:rsi]    || '–'

        boll   = md[:boll]   || {}
        bu     = fmt1(boll[:upper])
        bm     = fmt1(boll[:middle])
        bl     = fmt1(boll[:lower])

        macd = md[:macd]   || {}
        m_l  = macd[:macd] || '–'
        m_s  = macd[:signal] || '–'
        m_h  = macd[:hist] || '–'

        st_sig = md[:super] || 'neutral'
        hi20 = md[:hi20] || '–'
        lo20   = md[:lo20] || '–'
        lu     = md[:liq_up] ? 'yes' : 'no'
        ld     = md[:liq_dn] ? 'yes' : 'no'

        smc_pa_block = format_smc_price_action(md)

        expiry = md[:expiry] || 'N/A'
        # chain = format_options_chain(md[:options])
        chain = format_options_for_buying(md[:options])

        # Analysis context (optional)
        extra = context.to_s.strip
        extra_block = extra.empty? ? '' : "\n=== ADDITIONAL CONTEXT ===\n#{extra}\n"

        # India VIX
        vix_value = md[:vix] || '–'

        <<~PROMPT
          === EXPERT OPTIONS BUYING ANALYST ===

          You are an expert financial analyst specializing in the Indian equity & derivatives markets, with a focus on buying **#{md[:symbol]}** index options.
          **Response rule**: Lead with "AT A GLANCE" (5–8 bullets: Bias, strike, entry/SL/T1, hedge, exit). Then a very short details section. Total under 300 words so it fits one quick read.

          === CURRENT MARKET DATA ===
          India VIX: #{vix_value}%

          #{session_label} – **#{md[:symbol]}**

          Current Spot (LTP): ₹#{ltp}

          *Prev-day*   O #{pdo}  H #{pdh}  L #{pdl}  C #{pdc}
          *Current #{frame}*  O #{co}  H #{ch}  L #{cl}  C #{cc}  Vol #{cv}

          ATR-14 #{atr}  |  RSI-14 #{rsi}
          Bollinger  U #{bu}  M #{bm}  L #{bl}
          MACD  L #{m_l}  S #{m_s}  H #{m_h}
          Super-Trend  #{st_sig}
          20-bar range  H #{hi20} / L #{lo20}
          Liquidity grabs  up: #{lu}  down: #{ld}
          #{smc_pa_block}

          *Option-chain snapshot* (exp #{expiry}):
          #{chain}
          #{extra_block}=== ANALYSIS REQUIREMENTS ===
          **TASK — #{analysis_context_for(md[:session])}**

          **Bias rule (mandatory):** Your stated Bias (CALLS/PUTS/NEUTRAL) must match the data above: Super-Trend bearish + last candle bearish → PUTS or NEUTRAL; Super-Trend bullish + last candle bullish → CALLS; mixed/neutral → NEUTRAL. Do not say Bullish/CALLS when Super-Trend and last candle are bearish.
          **Bias → strike (mandatory):** If Bias is PUTS, primary must be a PE (not CE). If Bias is CALLS, primary must be a CE (not PE). Never recommend a CE when Bias is PUTS, or a PE when Bias is CALLS.

          **Data rule:** Use only strike and premium values from the *Option-chain snapshot* above. Do not invent numbers. All currency is ₹.
          **Entry & SL (mandatory):** Use the **exact** entry premium from the chain (e.g. ₹212.9). Use this **same** entry for both SL and T1: SL ₹ = entry × (1 − SL%); T1 ₹ = entry × (1 + T1%). Do not use one entry in one bullet and a different SL ₹ in another; keep one entry, one SL%, one SL ₹ throughout.

          **Format (mandatory):** Start with an "AT A GLANCE" block: 5–8 short bullets (Bias · Primary strike & entry/SL/T1 · Hedge if any · Exit time). Then abbreviate the sections below. Keep full response under 300 words. Exactly ONE primary strike, at most ONE hedge; no second primary.

          1) Directional probabilities from the current price (today's close vs now):
             • Strong upside (>0.5%) → CALL buying candidate
             • Strong downside (>0.5%) → PUT buying candidate
             • High-vol breakout (>1% either way) → straddle/strangle candidate
             • Explicitly state: "Close likely higher / lower / flat" with rationale.
             a) Intraday bias: State explicit bias: Bullish / Bearish / Range-bound (one word).
             b) Closing outcome buckets (today) with **price ranges**:
              • Significant upside (≥ +0.5%):   __%  | Close: ₹LOW–₹HIGH
              • Significant downside (≤ −0.5%): __%  | Close: ₹LOW–₹HIGH
              • Flat (−0.5%…+0.5%):             __%  | Close: ₹LOW–₹HIGH

          2) Strategy selection & strikes:
             • Pick exactly ONE primary idea + ONE hedge (CE/PE/straddle/strangle)
             • Specify strike(s), current premium range (₹), and Greeks relevance (Δ / Γ / ν / θ)
             • Prefer **ATM** strike (delta ≈ 0.35–0.55); do **not** suggest ITM for primary idea unless hedging. When trend is **confirmed and strong**: **NIFTY** → ATM+1 (e.g. 25350 CE if bullish); **SENSEX** → ATM+1 or ATM+2 in trend direction.
             • Use expiry **#{expiry}** for all options unless stated otherwise.
             a) OI & IV trends: Comment on changes vs prior session/week: rising/flat/falling OI, IV expansion/compression, and implications for strategy selection.
             b) Fundamentals & flows (if known): Briefly note macro cues (central bank, global futures, major news). If unknown, say "No material fundamental cues observed."

          3) Execution plan & risk:
             • Entry triggers; **stop-loss as % of option premium**: SL ₹ = entry × (1 − SL%). E.g. Entry ₹212.9, SL -10% → 212.9 × 0.90 = ₹191.61; SL -8% → 212.9 × 0.92 = ₹195.87. Do not use spot price for option SL.
             • **T1/T2 in option premium**: T1 ₹ = entry × (1 + T1%). E.g. Entry ₹212.9, T1 +15% → 212.9 × 1.15 = ₹244.84; T1 +50% → 212.9 × 1.50 = ₹319.35. Use ₹ only; do not mix spot levels with premium targets unless you label "spot target".
             • **Verify before writing:** If you state SL -8%, then SL ₹ must be entry × 0.92 (not 0.90). If you state T1 +15%, then T1 ₹ must be entry × 1.15 (not 1.50). Recompute so the % and ₹ match.
             • Time-based exit if no move (e.g., exit by 14:30 IST)
             • Comment on IV context (avoid paying extreme IV unless expecting expansion)
          4) **Closing range** (mandatory – you must output this line):
             • **Method to use:** Start with mid = Bollinger middle band. Base move = min(ATR-14, 0.75% of LTP).
               Scale by time remaining to close (linear), widen by +20% if India VIX > 14, shrink by −20% if VIX < 10.
               Round to nearest 5 points for NIFTY / 10 for BANKNIFTY.
             • **You must print exactly one line** in this format (replace placeholders with numbers):
              CLOSE RANGE: ₹<low>–₹<high> (<−x% to +y% from LTP>)
             • Example: CLOSE RANGE: ₹25200–₹25450 (−0.46% to +0.53% from LTP)
          5) Output (abbreviated; total under 300 words):
             • AT A GLANCE: 5–8 bullets (Bias · Strike & entry/SL/T1 · Hedge · Exit). Then:
             • Probability bands: one line (e.g. "≥50%: Flat 50%, Down 35%")
             • PRIMARY / HEDGE: one line each (strike, entry ₹ premium, SL % of premium / SL ₹, T1 ₹ premium or spot target)
             • ≤ 3 action bullets
             • **Bias:** exactly `Bias: CALLS` or `Bias: PUTS` or `Bias: NEUTRAL` (must match Super-Trend + last candle from data)
             • **CLOSE RANGE:** one line as instructed above

          **Check before submitting:** (1) Bias matches Super-Trend and last candle; (2) Bias PUTS → primary is PE; Bias CALLS → primary is CE; (3) Entry = exact premium from chain; same entry for SL ₹ and T1 ₹; (4) SL ₹ = entry × (1 − SL%) and T1 ₹ = entry × (1 + T1%) — e.g. -8% ⇒ ×0.92, +15% ⇒ ×1.15; (5) CLOSE RANGE line present; (6) One primary, one hedge only; (7) End with exactly one line: Bias: CALLS or Bias: PUTS or Bias: NEUTRAL.

          Bias: CALLS/PUTS/NEUTRAL
          — end of brief
        PROMPT
      end

      def build_options_buying_prompt(md, context = nil)
        # session_label = format_session_label(md[:session])
        session_label =
          case md[:session]
          when :pre_open   then '⏰ *Pre-open* session'
          when :post_close then '🔒 *Post-close* session'
          when :weekend    then '📅 *Weekend* (markets closed)'
          else                  '🟢 *Live* session'
          end

        # Extract key data
        ltp = md[:ltp]
        symbol = md[:symbol]
        expiry = md[:expiry] || 'N/A'
        vix_value = md[:vix] || '–'
        md[:regime] || {}

        # Format option chain for buying decisions
        chain = format_options_for_buying(md[:options])

        # Analysis context
        extra = context.to_s.strip
        extra_block = extra.empty? ? '' : "\n=== ADDITIONAL CONTEXT ===\n#{extra}\n"

        <<~PROMPT
          Based on the following option-chain snapshot for #{symbol}, suggest an instant options buying trade. Use **ATM** (delta near ±0.50); do not suggest ITM for primary buy. When trend is **confirmed and strong**: use **ATM+1** for NIFTY; **ATM+1 or ATM+2** for SENSEX (in trend direction). Evaluate IV, OI/volume shifts, and explain the rationale.

          === MARKET DATA ===
          #{session_label} – **#{symbol}**
          Spot Price: ₹#{ltp}
          India VIX: #{vix_value}%
          Expiry: #{expiry}

          #{format_technical_indicators(md)}
          #{format_smc_price_action(md)}

          === OPTION CHAIN DATA ===
          #{chain}
          #{extra_block}

          === TRADE SETUP REQUIRED ===
          Provide:
          1) **Trade Type**: Buy [CE/PE] [Strike] [Expiry]
          2) **Entry**: ₹[price] (limit near best bid/ask), **Reason**: [delta≈0.5 ATM, OI/IV context]
          3) **Stop Loss**: [20–30%] of premium or invalidation level; exact ₹ value
          4) **Take Profit**: [50–100%] premium or at [underlying target zone]
          5) **Position Sizing**: For ₹50,000 account with 3% risk = [lots] calculation
          6) **Validity**: [day/IOC]; avoid illiquid spreads
          7) **Key Levels**: Support/Resistance based on technical + option OI

          **Analysis Focus:**
          - Bias must match Super-Trend and last candle from the data; use only strike/premium from the chain; all currency ₹; one primary, one hedge.
          - Prefer ATM (delta ~0.5); avoid ITM for primary buy. Strong confirmed trend: NIFTY → ATM+1; SENSEX → ATM+1 or ATM+2 (in trend direction).
          - Use OI/Change in OI to infer support/resistance and sentiment
          - Consider IV levels - avoid buying during extreme IV unless expecting expansion
          - Factor in theta decay, especially for weekly expiries
          - Lot sizes: Nifty 50, Bank Nifty 15, Sensex 10

          **Risk Management:**
          - Account: ₹50,000 (adjust as needed)
          - Risk per trade: 2-5% of capital
          - Avoid positions >20% of account in single expiry
          - Time-based exit if no move by 2:30 PM

          === AVOID-BUYING CHECKS ===
          If any of the below hold, output: "Decision Gate: AVOID – <reason>"
          - IV regime likely to compress (IV high and falling or post-event)#{' '}
          - VIX falling and price range-bound
          - <48 hours to expiry without momentum; theta risk high (expiry-day scalps allowed if momentum confirmed)
          - Wide spreads or low OI/volume at chosen strike
          - No clear directional edge on this timeframe
          Otherwise output: "Decision Gate: BUY – <reason>"

          Decision Gate: BUY/AVOID – <one-line reason referencing IV/VIX/theta/liquidity>

          Format clearly for immediate execution with specific entry/exit levels.
        PROMPT
      end

      # Enhanced option chain formatting for buying decisions
      def format_options_for_buying(options)
        return 'No option-chain data available.' if options.blank?

        blocks = []

        # Present ATM first so the model defaults to it; then OTM/ITM for context
        {
          atm: 'ATM (Preferred for directional buy)',
          otm_call: 'OTM CALL (Lower Cost)',
          itm_call: 'ITM CALL (Higher Delta – avoid for primary)',
          otm_put: 'OTM PUT (Lower Cost)',
          itm_put: 'ITM PUT (Higher Delta – avoid for primary)'
        }.each do |key, label|
          opt = options[key]
          next unless opt

          strike = opt[:strike] || '?'
          ce = opt[:call] || {}
          pe = opt[:put] || {}

          # Extract key metrics for buying decisions
          ce_data = extract_option_metrics(opt, ce, 'ce')
          pe_data = extract_option_metrics(opt, pe, 'pe')

          blocks << format_strike_block(label, strike, ce_data, pe_data)
        end

        blocks.join("\n\n")
      end

      private

      def fmt1(x)
        x.is_a?(Numeric) ? x.round(1) : '–'
      end

      def fmt2(x)
        x.nil? ? '–' : x.to_f.round(2)
      end

      # Make the session wording explicit
      def analysis_context_for(session)
        case session
        when :pre_open   then 'Pre-market Preparation (for the open)'
        when :post_close then 'Post-market Analysis (for tomorrow)'
        when :weekend    then 'Weekend Analysis (for Monday opening)'
        else 'Live Intraday Analysis (right now)'
        end
      end

      def extract_option_metrics(opt, option_data, prefix)
        {
          ltp: opt[:"#{prefix}_ltp"] || option_data['last_price'] || option_data[:last_price],
          iv: opt[:"#{prefix}_iv"] || option_data['implied_volatility'] || option_data[:implied_volatility],
          oi: opt[:"#{prefix}_oi"] || option_data['oi'] || option_data[:oi],
          delta: opt[:"#{prefix}_delta"] || dig_any(option_data, 'greeks', 'delta'),
          theta: opt[:"#{prefix}_theta"] || dig_any(option_data, 'greeks', 'theta'),
          gamma: opt[:"#{prefix}_gamma"] || dig_any(option_data, 'greeks', 'gamma'),
          vega: opt[:"#{prefix}_vega"] || dig_any(option_data, 'greeks', 'vega'),
          bid: option_data['top_bid_price'] || option_data[:top_bid_price],
          ask: option_data['top_ask_price'] || option_data[:top_ask_price],
          volume: option_data['volume'] || option_data[:volume]
        }
      end

      def format_strike_block(label, strike, ce_data, pe_data)
        <<~STR.strip
          ► #{label} (#{strike})
            CALL: ₹#{fmt2(ce_data[:ltp])} | Bid/Ask: #{fmt2(ce_data[:bid])}/#{fmt2(ce_data[:ask])} | IV: #{fmt2(ce_data[:iv])}% | Δ: #{fmt2(ce_data[:delta])} | OI: #{fmt_large(ce_data[:oi])} | Vol: #{fmt_large(ce_data[:volume])}
            PUT:  ₹#{fmt2(pe_data[:ltp])} | Bid/Ask: #{fmt2(pe_data[:bid])}/#{fmt2(pe_data[:ask])} | IV: #{fmt2(pe_data[:iv])}% | Δ: #{fmt2(pe_data[:delta])} | OI: #{fmt_large(pe_data[:oi])} | Vol: #{fmt_large(pe_data[:volume])}
            Greeks: Γ #{fmt2(ce_data[:gamma])}/#{fmt2(pe_data[:gamma])} | θ #{fmt2(ce_data[:theta])}/#{fmt2(pe_data[:theta])} | ν #{fmt2(ce_data[:vega])}/#{fmt2(pe_data[:vega])}
        STR
      end

      def format_technical_indicators(md)
        ohlc = md[:ohlc] || {}

        <<~INDICATORS
          *Technical Snapshot*:
          OHLC: O #{ohlc[:open]} H #{ohlc[:high]} L #{ohlc[:low]} C #{ohlc[:close]}
          RSI: #{md[:rsi]} | ATR: #{md[:atr]} | Supertrend: #{md[:super]}
          Support/Resistance: #{md[:lo20]} / #{md[:hi20]}
          Bollinger: #{fmt1(md.dig(:boll, :lower))} - #{fmt1(md.dig(:boll, :upper))}
        INDICATORS
      end

      def format_smc_price_action(md)
        smc = md[:smc] || {}
        pa = md[:price_action] || {}
        return '' if smc.blank? && pa.blank?

        bias = smc[:structure_bias] || 'neutral'
        last_bos = smc[:last_bos] ? "Last BOS: #{smc[:last_bos]}" : 'Last BOS: –'
        sh = Array(smc[:swing_highs]).join(', ')
        sl = Array(smc[:swing_lows]).join(', ')
        fvg_b = smc[:fvg_bullish] ? "Bull FVG: #{smc[:fvg_bullish][:bottom]}–#{smc[:fvg_bullish][:top]}" : 'Bull FVG: –'
        fvg_s = smc[:fvg_bearish] ? "Bear FVG: #{smc[:fvg_bearish][:bottom]}–#{smc[:fvg_bearish][:top]}" : 'Bear FVG: –'
        ob_b = smc[:order_block_bullish] ? "Bull OB: #{smc[:order_block_bullish][:low]}–#{smc[:order_block_bullish][:high]}" : 'Bull OB: –'
        ob_s = smc[:order_block_bearish] ? "Bear OB: #{smc[:order_block_bearish][:low]}–#{smc[:order_block_bearish][:high]}" : 'Bear OB: –'
        inside = pa[:inside_bar] ? 'yes' : 'no'
        last_candle = if pa[:last_candle_bullish].nil?
                        '–'
                      else
                        (pa[:last_candle_bullish] ? 'bullish' : 'bearish')
                      end

        <<~SMC_PA
          *SMC & Price Action*
          Structure bias: #{bias}  |  #{last_bos}
          Swing highs (recent): #{sh.presence || '–'}  |  Swing lows: #{sl.presence || '–'}
          #{fvg_b}  |  #{fvg_s}
          #{ob_b}  |  #{ob_s}
          Inside bar (last): #{inside}  |  Last candle: #{last_candle}
        SMC_PA
      end

      def fmt_large(x)
        return '–' if x.nil?

        num = x.to_f
        return '–' if num.zero?

        case num
        when 0..999 then num.to_i.to_s
        when 1000..99_999 then "#{(num / 1000).round(1)}K"
        when 100_000..9_999_999 then "#{(num / 100_000).round(1)}L"
        else "#{(num / 10_000_000).round(1)}Cr"
        end
      end

      def dig_any(h, *path)
        h.is_a?(Hash) ? h.dig(*path) : nil
      end
    end
  end
end
