module Market
  class PromptBuilder
    class << self

      def build_prompt(md, context: nil, trade_type: :analysis)
        case trade_type
        when :options_buying
          build_options_buying_prompt(md, context)
        else
          build_analysis_prompt(md, context) # Your existing method
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
        session_label = format_session_label(md[:session])
        
        # Extract key data
        ltp = md[:ltp]
        symbol = md[:symbol]
        expiry = md[:expiry] || 'N/A'
        vix_value = md[:vix] || '–'
        
        # Format option chain for buying decisions
        chain = format_options_for_buying(md[:options])
        
        # Analysis context
        extra = context.to_s.strip
        extra_block = extra.empty? ? '' : "\n=== ADDITIONAL CONTEXT ===\n#{extra}\n"

        <<~PROMPT
          Based on the following option-chain snapshot for #{symbol}, suggest an instant options buying trade. Use ATM or slightly ITM strikes guided by delta near ±0.50, evaluate IV, OI/volume shifts, and explain the rationale.

          === MARKET DATA ===
          #{session_label} – **#{symbol}**
          Spot Price: ₹#{ltp}
          India VIX: #{vix_value}%
          Expiry: #{expiry}

          #{format_technical_indicators(md)}

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
          - Delta around 0.5 for ATM exposure and responsive premium
          - Use OI/Change in OI to infer support/resistance and sentiment
          - Consider IV levels - avoid buying during extreme IV unless expecting expansion
          - Factor in theta decay, especially for weekly expiries
          - Lot sizes: Nifty 50, Bank Nifty 15, Sensex 10

          **Risk Management:**
          - Account: ₹50,000 (adjust as needed)
          - Risk per trade: 2-5% of capital
          - Avoid positions >20% of account in single expiry
          - Time-based exit if no move by 2:30 PM

          Format clearly for immediate execution with specific entry/exit levels.
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