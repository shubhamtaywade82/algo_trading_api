module TelegramBot
  class CommandHandler < ApplicationService
    ANALYSIS_CACHE_KEY = 'portfolio:institutional:last_run'.freeze

    SYMBOL_CONFIG = {
      'nifty' => { symbol: 'NIFTY', exchange: :nse },
      'banknifty' => { symbol: 'BANKNIFTY', exchange: :nse },
      'sensex' => { symbol: 'SENSEX', exchange: :bse }
    }.freeze

    OPTION_CONFIG = {
      'ce' => :ce,
      'call' => :ce,
      'pe' => :pe,
      'put' => :pe
    }.freeze

    def initialize(chat_id:, command:)
      @cid = chat_id
      @cmd = command.to_s.strip
    end

    def call
      case @cmd
      when '/start', '/help' then show_help
      when '/portfolio'  then quick_portfolio_brief
      when '/positions'  then positions_brief
      when '/portfolio_full' then institutional_portfolio_brief
      when '/funds', '/balance' then funds_brief
      when '/nifty_analysis' then run_market_analysis('NIFTY')
      when '/sensex_analysis' then run_market_analysis('SENSEX', exchange: :bse)
      when '/bank_nifty_analysis', '/banknifty_analysis' then run_market_analysis('BANKNIFTY')
      when '/nifty_options' then run_options_buying_analysis('NIFTY')
      when '/banknifty_options' then run_options_buying_analysis('BANKNIFTY')
      when '/sensex_options' then run_options_buying_analysis('SENSEX', exchange: :bse)
      when '/options_avoid_check' then options_avoid_check
      when '/gift_nifty_analysis' then gift_nifty_analysis
      when '/oi_snapshot' then oi_snapshot
      when '/market_summary' then market_summary
      when '/expiry_roadmap' then expiry_roadmap
      when '/screener', '/stocks_screener' then run_stocks_screener
      when '/market_sentiment' then market_sentiment_brief
      when '/crypto_scan' then run_crypto_scan
      when '/crypto_config' then crypto_config_brief
      when %r{\A/crypto_analysis(?:\s+(.+))?\z} then run_crypto_analysis(Regexp.last_match(1))
      else
        handled = try_manual_signal!
        TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid) unless handled
      end
    end

    # --------------------------------------------------------------
    private

    def dhan_auth_error?(e)
      name = e.class.name.to_s
      msg  = e.message.to_s
      name.include?('Authentication') || name.include?('Unauthorized') || msg.include?('401')
    end

    def notify_analysis_error(e)
      msg = dhan_auth_error?(e) ? '🔐 Dhan session expired or invalid. Please refresh your token or re-link your account.' : "🚨 Error running analysis – #{e.message}"
      TelegramNotifier.send_message(msg, chat_id: @cid)
    end

    def try_manual_signal!
      parsed = parse_manual_signal(@cmd)
      return false unless parsed

      TelegramBot::ManualSignalTrigger.call(
        chat_id: @cid,
        symbol: parsed[:symbol],
        option: parsed[:option],
        exchange: parsed[:exchange]
      )

      true
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ Manual signal failed – #{e.class}: #{e.message}"
      TelegramNotifier.send_message("🚨 Error triggering manual signal – #{e.message}", chat_id: @cid)
      true
    end

    def parse_manual_signal(command)
      normalized = command.to_s.strip.downcase
      normalized = normalized.delete_prefix('/')
      normalized = normalized.tr('_-', '  ')
      parts = normalized.split(/\s+/)
      return if parts.size < 2

      symbol_key = parts[0]
      option_key = parts[1]

      symbol_config = SYMBOL_CONFIG[symbol_key]
      option = OPTION_CONFIG[option_key]
      return unless symbol_config && option

      {
        symbol: symbol_config[:symbol],
        exchange: symbol_config[:exchange],
        option: option
      }
    end

    def quick_portfolio_brief
      typing_ping
      holdings = Dhanhq::API::Portfolio.holdings
      if holdings.blank?
        return TelegramNotifier.send_message('📭 No holdings found. Add positions to get a portfolio summary.', chat_id: @cid)
      end

      result = PortfolioInsights::Analyzer.call(
        dhan_holdings: holdings,
        interactive: true
      )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      notify_analysis_error(e)
    end

    def run_options_buying_analysis(symbol, exchange: :nse)
      typing_ping
      MarketAnalysisJob.perform_later(@cid, symbol, exchange: exchange, trade_type: :options_buying)
      TelegramNotifier.send_message("🎯 **#{symbol} Options Buying Setup**", chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      notify_analysis_error(e)
    end

    def run_market_analysis(symbol, exchange: :nse)
      typing_ping
      MarketAnalysisJob.perform_later(@cid, symbol, exchange: exchange)
      TelegramNotifier.send_message("📊 Analysis started for #{symbol}. You'll get a detailed report shortly.", chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      notify_analysis_error(e)
    end

    def institutional_portfolio_brief
      typing_ping
      holdings = Dhanhq::API::Portfolio.holdings
      if holdings.blank?
        return TelegramNotifier.send_message('📭 No holdings found. Add positions to get a full portfolio analysis.', chat_id: @cid)
      end

      balance   = Dhanhq::API::Funds.balance
      positions = Dhanhq::API::Portfolio.positions

      result = PortfolioInsights::InstitutionalAnalyzer.call(
        dhan_holdings: holdings,
        dhan_positions: positions,
        dhan_balance: balance,
        interactive: true
      )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
      Rails.cache.write(ANALYSIS_CACHE_KEY, Time.now.utc, expires_in: 25.hours) if result.present?
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      notify_analysis_error(e)
    end

    def run_stocks_screener
      typing_ping
      # Adjust universe/frame/limits from chat text later if you want.
      Screeners::StocksScreener.call(
        universe: :nifty100,
        session: :live,
        frame: '15m',
        lookback: 20,
        limit: 20,
        min_price: 80,
        min_avg_vol: 75_000,
        optionable: true,
        push_to_telegram: true
      )
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ StocksScreener – #{e.class}: #{e.message}"
      TelegramNotifier.send_message("🚨 Screener error – #{e.message}", chat_id: @cid)
    end

    def positions_brief
      typing_ping
      positions = Dhanhq::API::Portfolio.positions
      return TelegramNotifier.send_message('📭 No open positions. Add positions to get a brief.', chat_id: @cid) if positions.blank?

      result = PositionInsights::Analyzer.call(
        dhan_positions: positions,
        interactive: true
      )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      notify_analysis_error(e)
    end

    def options_avoid_check # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
      typing_ping
      inst = instrument_for('NIFTY', :nse)
      vix_inst = Instrument.find_by(security_id: 21)
      return TelegramNotifier.send_message('⚠️ Instrument or India VIX not found.', chat_id: @cid) unless inst && vix_inst

      chain = inst.fetch_option_chain(inst.expiry_list&.first)
      return TelegramNotifier.send_message('⚠️ Could not fetch option chain for NIFTY.', chat_id: @cid) unless chain

      analyzed = Market::OptionChainAnalyzer.new(chain, inst.ltp.to_f).extract_data
      vix = vix_inst.ltp.to_f
      atm = analyzed&.dig(:atm) || {}
      ce_iv = (atm[:ce_iv] || atm.dig(:call, 'implied_volatility')).to_f
      pe_iv = (atm[:pe_iv] || atm.dig(:put, 'implied_volatility')).to_f
      iv_arr = [ce_iv, pe_iv].reject(&:zero?)
      iv_atm = iv_arr.any? ? (iv_arr.sum / iv_arr.size.to_f).round(2) : 0
      ce_theta = atm.dig(:call, 'greeks', 'theta') || atm[:ce_theta]
      pe_theta = atm.dig(:put, 'greeks', 'theta') || atm[:pe_theta]
      theta_str = [ce_theta, pe_theta].compact.map { |t| t.to_f.round(1) }.join(' / ').presence || '–'

      avoid = vix >= 16 || iv_atm >= 18
      verdict = avoid ? '⚠️ Avoid buying premium (high IV/VIX)' : '✅ OK to consider buying'
      msg = <<~TEXT.strip
        📉 *Options avoid check* (NIFTY nearest expiry)
        India VIX: #{vix.round(2)}% | ATM IV: #{iv_atm}% | θ CE/PE: #{theta_str}
        #{verdict}
      TEXT
      TelegramNotifier.send_message(msg, chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] options_avoid_check – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def gift_nifty_analysis
      # GIFT Nifty (SGX) – not in Dhan index segment; suggest NIFTY analysis
      TelegramNotifier.send_message(
        '⏳ GIFT Nifty (SGX) is not configured for this app. Use /nifty_analysis for NIFTY.',
        chat_id: @cid
      )
    end

    def oi_snapshot # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
      typing_ping
      inst = instrument_for('NIFTY', :nse)
      return TelegramNotifier.send_message('⚠️ NIFTY instrument not found.', chat_id: @cid) unless inst

      chain = inst.fetch_option_chain(inst.expiry_list&.first)
      return TelegramNotifier.send_message('⚠️ Could not fetch NIFTY option chain.', chat_id: @cid) unless chain

      analyzed = Market::OptionChainAnalyzer.new(chain, inst.ltp.to_f).extract_data
      return TelegramNotifier.send_message('⚠️ No option data extracted.', chat_id: @cid) if analyzed.blank?

      atm = analyzed[:atm] || {}
      ce_oi = (atm[:ce_oi] || atm.dig(:call, 'oi')).to_f
      pe_oi = (atm[:pe_oi] || atm.dig(:put, 'oi')).to_f
      ce_iv = (atm[:ce_iv] || atm.dig(:call, 'implied_volatility')).to_f.round(2)
      pe_iv = (atm[:pe_iv] || atm.dig(:put, 'implied_volatility')).to_f.round(2)
      strike = atm[:strike] || '–'
      fmt_oi = ->(x) { x >= 1_000_000 ? "#{(x / 1_000_000).round(1)}M" : "#{(x / 1000).round(1)}K" }

      msg = <<~TEXT.strip
        📊 *OI snapshot* – NIFTY ATM #{strike} (nearest expiry)
        CE: OI #{fmt_oi.call(ce_oi)} | IV #{ce_iv}%
        PE: OI #{fmt_oi.call(pe_oi)} | IV #{pe_iv}%
      TEXT
      TelegramNotifier.send_message(msg, chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] oi_snapshot – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def market_summary
      typing_ping
      vix_inst = Instrument.find_by(security_id: 21)
      indices = [
        ['NIFTY', :nse],
        ['BANKNIFTY', :nse],
        ['SENSEX', :bse]
      ]
      lines = indices.filter_map do |symbol, exchange|
        inst = instrument_for(symbol, exchange)
        next unless inst

        ltp = inst.ltp
        next if ltp.blank?

        "• #{symbol}: ₹#{PriceMath.round_tick(ltp)}"
      end
      vix_line = vix_inst ? "• India VIX: #{vix_inst.ltp&.round(2)}%" : nil
      lines << vix_line if vix_line

      if lines.empty?
        TelegramNotifier.send_message('⚠️ Could not fetch index LTP or VIX.', chat_id: @cid)
        return
      end

      msg = "📈 *Market summary*\n#{lines.join("\n")}"
      TelegramNotifier.send_message(msg, chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] market_summary – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def expiry_roadmap # rubocop:disable Metrics/AbcSize, Metrics/PerceivedComplexity
      typing_ping
      inst = instrument_for('NIFTY', :nse)
      return TelegramNotifier.send_message('⚠️ NIFTY instrument not found.', chat_id: @cid) unless inst

      expiries = inst.expiry_list
      return TelegramNotifier.send_message('⚠️ No NIFTY expiries found.', chat_id: @cid) if expiries.blank?

      next_four = expiries.first(4).map { |e| e.to_s.sub(/\A(\d{4})-(\d{2})-(\d{2})\z/, '\3-\2-\1') }
      chain = inst.fetch_option_chain(expiries.first)
      atm_iv = nil
      if chain
        analyzed = Market::OptionChainAnalyzer.new(chain, inst.ltp.to_f).extract_data
        atm = analyzed&.dig(:atm)
        if atm
          ce = (atm[:ce_iv] || atm.dig(:call, 'implied_volatility')).to_f
          pe = (atm[:pe_iv] || atm.dig(:put, 'implied_volatility')).to_f
          arr = [ce, pe].reject(&:zero?)
          atm_iv = arr.any? ? (arr.sum / arr.size.to_f).round(2) : nil
        end
      end

      msg = "📅 *Expiry roadmap* – NIFTY\nNext: #{next_four.join(', ')}"
      msg += "\nNearest expiry ATM IV: #{atm_iv}%" if atm_iv
      TelegramNotifier.send_message(msg.strip, chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] expiry_roadmap – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def run_crypto_scan
      typing_ping
      results = Crypto::Scanner.call
      if results.empty?
        TelegramNotifier.send_message(
          'ℹ️ Crypto scan complete: No qualifying setups found across configured symbols.',
          chat_id: @cid
        )
      else
        results.each do |r|
          next unless r.setup

          msg = Crypto::SetupFormatter.call(r.setup)
          TelegramNotifier.send_message(msg, chat_id: @cid)
        end
      end
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ crypto_scan failed – #{e.class}: #{e.message}"
      notify_crypto_error(e)
    end

    def run_crypto_analysis(raw_symbol = nil)
      typing_ping
      sym = normalize_crypto_symbol(raw_symbol)

      analyzer = Crypto::Analyzer.new(sym)
      reports = analyzer.reports
      return TelegramNotifier.send_message("❌ Could not fetch Binance market data for #{sym}.", chat_id: @cid) if reports.nil?

      lines = build_crypto_analysis_lines(sym, reports)
      TelegramNotifier.send_message(lines.join("\n"), chat_id: @cid)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ crypto_analysis failed – #{e.class}: #{e.message}"
      notify_crypto_error(e)
    end

    def notify_crypto_error(e)
      if e.is_a?(Crypto::Binance::GeoblockedError) || e.message.to_s.include?('451') || e.message.to_s.include?('restricted location')
        msg = <<~TEXT.strip
          🚫 *Binance API Geoblocked (HTTP 451)*
          Binance restricts public API access from this server's datacenter IP location.

          *Quick Solutions:*
          1️⃣ Set `CRYPTO_BINANCE_BASE` in Render Env Vars to a non-US proxy mirror or Cloudflare Worker (e.g. `https://your-proxy.workers.dev`).
          2️⃣ Or change your Render service region to Singapore or Frankfurt.
        TEXT
        TelegramNotifier.send_message(msg, chat_id: @cid, parse_mode: 'Markdown')
      else
        TelegramNotifier.send_message("🚨 Error running crypto analysis – #{e.message}", chat_id: @cid)
      end
    end

    def normalize_crypto_symbol(raw_symbol)
      sym = raw_symbol.presence || Crypto::Config.symbols.first || 'SOLUSDT'
      sym = sym.to_s.strip.upcase
      sym.end_with?('USDT') ? sym : "#{sym}USDT"
    end

    def build_crypto_analysis_lines(sym, reports)
      lines = ["🪙 *Crypto SMC Analysis – #{sym}*"]
      Crypto::Config::TIMEFRAMES.each do |tf|
        rep = reports[tf]
        next unless rep

        s = rep.summary
        price_fmt = Crypto::Formatting.price(s[:price])
        lines << "• *#{tf.upcase}*: #{s[:bias].upcase} | #{price_fmt} | Zone: #{s[:zone] || 'N/A'} | Event: #{s[:last_event] || 'None'}"
      end

      setup = Crypto::SetupDetector.call(symbol: sym, reports: reports)
      lines << ''
      lines << if setup
                 Crypto::SetupFormatter.call(setup)
               else
                 "ℹ️ _No active setup meeting score >= #{Crypto::Config.min_score} & R:R >= #{Crypto::Config.min_risk_reward}_"
               end
      lines
    end

    def show_help
      msg = <<~TEXT.strip
        🤖 *Algo Trading API — Command Guide*

        📈 *Indian Markets (DhanHQ)*
        • /nifty_analysis — NIFTY technical & option chain report
        • /bank_nifty_analysis — BANKNIFTY analysis
        • /sensex_analysis — SENSEX analysis
        • /nifty_options — NIFTY options buying setup
        • /banknifty_options — BANKNIFTY options buying setup
        • /sensex_options — SENSEX options buying setup
        • /options_avoid_check — Check if IV/VIX favors buying options
        • /oi_snapshot — NIFTY ATM Open Interest & IV snapshot
        • /market_summary — Live index LTPs and India VIX
        • /expiry_roadmap — Index expiry roadmap & ATM IV
        • /screener — Run NIFTY 100 stock screener
        • /market_sentiment — Market sentiment & institutional flow

        💼 *Portfolio & Account*
        • /portfolio — Quick portfolio holdings summary
        • /positions — Live open positions & P&L
        • /portfolio_full — Full institutional risk analysis
        • /funds — Account funds, margin & collateral limits

        🪙 *Crypto Futures (Binance USD-M)*
        • /crypto_analysis — SMC multi-timeframe report (e.g. `/crypto_analysis BTCUSDT`)
        • /crypto_scan — Scan crypto futures pairs for trade setups
        • /crypto_config — Active crypto scanner settings & parameters

        ⚡ *Manual Signals*
        • `/nifty_ce`, `/nifty_pe`, `/banknifty_ce`, `/banknifty_pe`, `/sensex_ce`, `/sensex_pe`
      TEXT
      TelegramNotifier.send_message(msg, chat_id: @cid, parse_mode: 'Markdown')
    end

    def funds_brief
      typing_ping
      balance = Dhanhq::API::Funds.balance
      return TelegramNotifier.send_message('⚠️ Could not fetch fund limits from Dhan.', chat_id: @cid) if balance.blank?

      avail = balance['availMargin'] || balance['available_balance'] || balance[:available_balance] || 0
      used = balance['utilisedMargin'] || balance['used_margin'] || balance[:used_margin] || 0

      msg = <<~TEXT.strip
        💰 *Dhan Funds & Margin Status*
        Available Margin: ₹#{PriceMath.round_tick(avail.to_f)}
        Utilised Margin: ₹#{PriceMath.round_tick(used.to_f)}
      TEXT
      TelegramNotifier.send_message(msg, chat_id: @cid, parse_mode: 'Markdown')
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] funds_brief – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def market_sentiment_brief
      typing_ping
      service = Market::SentimentService.new
      res = service.call
      return TelegramNotifier.send_message('⚠️ Market sentiment analysis unavailable.', chat_id: @cid) if res.blank?

      msg = "📊 *Market Sentiment Analysis*\n#{res}"
      TelegramNotifier.send_message(msg, chat_id: @cid, parse_mode: 'Markdown')
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] market_sentiment – #{e.class}: #{e.message}"
      notify_analysis_error(e)
    end

    def crypto_config_brief
      msg = <<~TEXT.strip
        ⚙️ *Crypto SMC Scanner Configuration*
        Enabled: #{Crypto::Config.enabled?}
        Symbols: #{Crypto::Config.symbols.join(', ')}
        Timeframes: #{Crypto::Config::TIMEFRAMES.join(', ')} (Execution: #{Crypto::Config::EXECUTION_TIMEFRAME})
        Stream Timeframes: #{Crypto::Config.stream_timeframes.join(', ')}
        Min Score: #{Crypto::Config.min_score} | Min R:R: #{Crypto::Config.min_risk_reward}
        Cooldown: #{(Crypto::Config.cooldown_seconds / 60).round} min
      TEXT
      TelegramNotifier.send_message(msg, chat_id: @cid, parse_mode: 'Markdown')
    end

    def instrument_for(symbol, exchange)
      Instrument.lookup_by_symbol(symbol, exchange: exchange)
    end

    def send_not_implemented(description)
      TelegramNotifier.send_message(
        "⏳ #{description} – not implemented yet.",
        chat_id: @cid
      )
    end
  end
end
