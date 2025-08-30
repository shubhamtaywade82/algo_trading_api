module Market
  class PromptBuilder
    class << self
      # Add optional `context:` and keep everything you already have
      def build_prompt(md, context: nil)
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

        # LTP (explicit line like old prompt; fall back to close)
        ltp = md[:ltp] || cc

        # Indicators (kept)
        atr = md[:atr] || '–'
        rsi = md[:rsi] || '–'

        boll = md[:boll] || {}
        bu   = fmt1(boll[:upper])
        bm   = fmt1(boll[:middle])
        bl   = fmt1(boll[:lower])

        macd = md[:macd] || {}
        m_l  = macd[:macd]   || '–'
        m_s  = macd[:signal] || '–'
        m_h  = macd[:hist]   || '–'

        st_sig = md[:super] || 'neutral'

        hi20 = md[:hi20] || '–'
        lo20 = md[:lo20] || '–'
        lu   = md[:liq_up] ? 'yes' : 'no'
        ld   = md[:liq_dn] ? 'yes' : 'no'

        expiry = md[:expiry] || 'N/A'
        chain  = format_options_chain(md[:options])

        # Analysis context (optional)
        extra = context.to_s.strip
        extra_block = extra.empty? ? '' : "\n=== ADDITIONAL CONTEXT ===\n#{extra}\n"

        # India VIX
        vix_value = md[:vix] || '–'

        <<~PROMPT
          === EXPERT OPTIONS BUYING ANALYST ===

          You are an expert financial analyst specializing in the Indian equity & derivatives markets, with a focus on buying **#{md[:symbol]}** index options.
          NOTE: Please make the text consise and quick readable

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

          *Option-chain snapshot* (exp #{expiry}):
          #{chain}
          #{extra_block}=== ANALYSIS REQUIREMENTS ===
          **TASK — #{analysis_context_for(md[:session])}**

          1) Directional probabilities from the current price (today’s close vs now):
             • Strong upside (>0.5%) → CALL buying candidate
             • Strong downside (>0.5%) → PUT buying candidate
             • High-vol breakout (>1% either way) → straddle/strangle candidate
             • Explicitly state: “Close likely higher / lower / flat” with rationale.
             a) Intraday bias: State explicit bias: Bullish / Bearish / Range-bound (one word).
             b) Closing outcome buckets (today) with **price ranges**:
              • Significant upside (≥ +0.5%):   __%  | Close: ₹LOW–₹HIGH
              • Significant downside (≤ −0.5%): __%  | Close: ₹LOW–₹HIGH
              • Flat (−0.5%…+0.5%):             __%  | Close: ₹LOW–₹HIGH

          2) Strategy selection & strikes:
             • Pick exactly ONE primary idea + ONE hedge (CE/PE/straddle/strangle)
             • Specify strike(s), current premium range (₹), and Greeks relevance (Δ / Γ / ν / θ)
             • Prefer delta ≈ 0.35–0.55 for directional buys unless IV regime suggests otherwise
             • Use expiry **#{expiry}** for all options unless stated otherwise.
             a) OI & IV trends: Comment on changes vs prior session/week: rising/flat/falling OI, IV expansion/compression, and implications for strategy selection.
             b) Fundamentals & flows (if known): Briefly note macro cues (central bank, global futures, major news). If unknown, say “No material fundamental cues observed.”

          3) Execution plan & risk:
             • Entry triggers, stop-loss (% of premium), T1 & T2 targets
             • Time-based exit if no move (e.g., exit by 14:30 IST)
             • Comment on IV context (avoid paying extreme IV unless expecting expansion)
          4) **Closing range** (mandatory line):
             • **Method to use:** Start with mid = Bollinger middle band. Base move = min(ATR-14, 0.75% of LTP).
               Scale by time remaining to close (linear), widen by +20% if India VIX > 14, shrink by −20% if VIX < 10.
               Round to nearest 5 points for NIFTY / 10 for BANKNIFTY.
             • **Print exactly this line:**
              `CLOSE RANGE: ₹<low>–₹<high> (<−x% to +y% from LTP>)`
          5) Output format (concise, trade-desk ready):
             • Probability bands (≥30 %, ≥50 %, ≥70 %) with one-line rationale
             • PRIMARY: <strategy, strikes, entry ₹, SL %, T1/T2 ₹, reasoning>
             • HEDGE:   <strategy, strikes, entry ₹, SL %, T1/T2 ₹, reasoning>
             • ≤ 4 crisp action bullets for immediate execution
             • **ONE-LINE BIAS**: Add one final line **exactly** as `Bias: CALLS` or `Bias: PUTS` or `Bias: NEUTRAL`
               (pick one based on directional probabilities, IV context and Greeks). This line must appear
               on its own, right before the closing marker below.
             • **Also include the line above for closing range.**

          Finish with an actionable summary:
            – Exact strike(s) to buy
            – Suggested stop-loss & target
          Bias: CALLS/PUTS/NEUTRAL   # ← print one of these three EXACTLY
          — end of brief
        PROMPT
      end

      private

      def fmt1(x)
        x.is_a?(Numeric) ? x.round(1) : '–'
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

      def dig_any(h, *path)
        h.is_a?(Hash) ? h.dig(*path) : nil
      end
    end
  end
end