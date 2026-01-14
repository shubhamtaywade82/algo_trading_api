module Market
  class PromptBuilder
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
          - Prefer strikes in ±1% ATM window with delta 0.35–0.55 and adequate OI/liquidity. Avoid illiquid strikes.
          - Use CE when confluence is bullish; PE when bearish. If mixed/weak, return NO_TRADE with reasons.
          - Risk budget: default 1–2% of capital; never exceed user’s max loss per trade. Bracket orders via DhanHQ SuperOrder.
          - Respect broker mapping (securityId, exchangeSegment) if provided.

          OUTPUT STYLE
          Produce a concise, human-readable trading desk brief that follows any formatting instructions provided in the user prompt (probability bands, PRIMARY/HEDGE lines, CLOSE RANGE, Bias line, closing marker).
          - Do **not** return JSON or structured data; stick to readable text with short bullets.
          - Keep recommendations actionable with strikes, entry/SL/TP, and rationale tied to the data in the prompt.

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
             - SL/TP derived via option ATR or spot ATR translated to option ticks; add trailing if trend day

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
             • Prefer delta ≈ 0.35–0.55 for directional buys unless IV regime suggests otherwise
             • Use expiry **#{expiry}** for all options unless stated otherwise.
             a) OI & IV trends: Comment on changes vs prior session/week: rising/flat/falling OI, IV expansion/compression, and implications for strategy selection.
             b) Fundamentals & flows (if known): Briefly note macro cues (central bank, global futures, major news). If unknown, say "No material fundamental cues observed."

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

      def build_options_buying_prompt(md, context = nil)
        #session_label = format_session_label(md[:session])
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
        reg = md[:regime] || {}
        regime_note = "IV@ATM: #{fmt1(reg[:iv_atm])}% | VIX: #{fmt1(reg[:vix])} (high? #{reg[:vix_high]} / low? #{reg[:vix_low]})"

        
        # Format option chain for buying decisions
        chain = format_options_for_buying(md[:options])
        
        # Analysis context
        extra = context.to_s.strip
        extra_block = extra.empty? ? '' : "\n=== ADDITIONAL CONTEXT ===\n#{extra}\n"

        smc_15 = md.dig(:smc, :m15)
        smc_5 = md.dig(:smc, :m5)
        val_15 = md.dig(:value, :m15) || {}
        val_5 = md.dig(:value, :m5) || {}

        structure_block = <<~STRUCT
          === 15m STRUCTURE (SMC) ===
          Market Structure: #{smc_15&.market_structure || 'unknown'}
          Last Swing High: #{fmt2(smc_15&.last_swing_high&.dig(:price))}
          Last Swing Low: #{fmt2(smc_15&.last_swing_low&.dig(:price))}
          Last BOS: #{smc_15&.last_bos ? "#{smc_15.last_bos[:direction]} @ #{fmt2(smc_15.last_bos[:level])}" : 'none'}

          === 5m STRUCTURE (SMC) ===
          Market Structure: #{smc_5&.market_structure || 'unknown'}
          Last BOS: #{smc_5&.last_bos ? "#{smc_5.last_bos[:direction]} @ #{fmt2(smc_5.last_bos[:level])}" : 'none'}
        STRUCT

        value_block = <<~VALUE
          === VALUE ZONES (VWAP/AVWAP/AVRZ) ===
          15m VWAP: #{fmt2(val_15[:vwap])} | 15m AVWAP(BOS): #{fmt2(val_15[:avwap_bos])}
          15m AVRZ: low #{fmt2(val_15.dig(:avrz, :low))} | mid #{fmt2(val_15.dig(:avrz, :mid))} | high #{fmt2(val_15.dig(:avrz, :high))} (#{val_15.dig(:avrz, :regime)})

          5m VWAP: #{fmt2(val_5[:vwap])} | 5m AVWAP(BOS): #{fmt2(val_5[:avwap_bos])}
          5m AVRZ: low #{fmt2(val_5.dig(:avrz, :low))} | mid #{fmt2(val_5.dig(:avrz, :mid))} | high #{fmt2(val_5.dig(:avrz, :high))} (#{val_5.dig(:avrz, :regime)})
        VALUE

        <<~PROMPT
          You must output exactly ONE decision using the canonical spec below.
          GLOBAL RULES (NON-NEGOTIABLE):
          - Exact keys, exact casing.
          - No prose paragraphs.
          - No missing fields.
          - Do NOT invent structure/levels/zones; only use the provided SMC/VWAP/AVRZ and option-chain snapshot.
          - If uncertain, output NO_TRADE.

          === MARKET DATA ===
          #{session_label} – **#{symbol}**
          Spot Price: ₹#{ltp}
          India VIX: #{vix_value}%
          Expiry: #{expiry}

          #{format_technical_indicators(md)}

          #{structure_block}
          #{value_block}

          === OPTION CHAIN DATA ===
          #{chain}
          #{extra_block}

          === CANONICAL RESPONSE SPEC (EXACT) ===

          [NO_TRADE]
          Decision: NO_TRADE
          Instrument: #{symbol}
          Market Bias: RANGE / UNCLEAR
          Reason: <one sentence>
          Risk Note: <one sentence>
          Re-evaluate When:
          - <condition 1>
          - <condition 2>

          [WAIT]
          Decision: WAIT
          Instrument: #{symbol}
          Bias: <e.g. BULLISH (15m) / BEARISH (15m)>
          No Trade Because:
          - <reason 1>
          - <reason 2>
          Trigger Conditions:
          - <trigger 1>
          - <trigger 2>
          Preferred Option (If Triggered):
          - Type: CE|PE
          - Strike Zone: <range>
          - Expected Premium Zone: <range>
          Reason: <one sentence>

          [BUY]
          Decision: BUY
          Instrument: #{symbol}
          Bias: BULLISH / BEARISH
          Option:
          - Type: CE|PE
          - Strike: <integer>
          - Expiry: #{expiry}
          Execution:
          - Entry Premium: <number>
          - Stop Loss Premium: <number>
          - Target Premium: <number>
          - Risk Reward: <number>
          Underlying Context:
          - Spot Above/Spot Below: <number> (VWAP/BOS reference)
          - Invalidation Below/Invalidation Above: <number> (15m structure)
          Exit Rules:
          - SL Hit on premium
          - OR Spot closes below/above <number> on 5m
          - OR VWAP rule using 5m candles
          Reason: <one sentence>

          ENFORCEMENT:
          - One decision only.
          - For BUY: RR >= 1.5 and premium SL < entry < target.
          - For NO_TRADE: do not include Option/Execution/Exit Rules.
          - For WAIT: do not include execution prices (no Entry/SL/Target/RR).
        PROMPT
      end

      # Enhanced option chain formatting for buying decisions
      def format_options_for_buying(options)
        return 'No option-chain data available.' if options.blank?

        blocks = []
        
        # Focus on tradeable strikes with good liquidity
        {
          itm_call: 'ITM CALL (Higher Delta)',
          atm: 'ATM (Balanced Risk/Reward)', 
          otm_call: 'OTM CALL (Lower Cost)',
          itm_put: 'ITM PUT (Higher Delta)',
          otm_put: 'OTM PUT (Lower Cost)'
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

      def fmt_large(x)
        return '–' if x.nil?
        
        num = x.to_f
        return '–' if num.zero?
        
        case num
        when 0..999 then num.to_i.to_s
        when 1000..99999 then "#{(num/1000).round(1)}K"
        when 100000..9999999 then "#{(num/100000).round(1)}L"
        else "#{(num/10000000).round(1)}Cr"
        end
      end 

      def dig_any(h, *path)
        h.is_a?(Hash) ? h.dig(*path) : nil
      end
    end
  end
end
