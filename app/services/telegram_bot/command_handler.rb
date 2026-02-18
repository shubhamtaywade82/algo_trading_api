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
      when '/portfolio'  then quick_portfolio_brief
      when '/positions'  then positions_brief
      when '/portfolio_full'  then institutional_portfolio_brief
      when '/nifty_analysis' then run_market_analysis('NIFTY')
      when '/sensex_analysis' then run_market_analysis('SENSEX', exchange: :bse)
      when '/bank_nifty_analysis' then run_market_analysis('BANKNIFTY')
      when '/nifty_options' then run_options_buying_analysis('NIFTY')
      when '/banknifty_options' then run_options_buying_analysis('BANKNIFTY')
      when '/sensex_options' then run_options_buying_analysis('SENSEX', exchange: :bse)
      when '/options_avoid_check' then options_avoid_check
      when '/gift_nifty_analysis' then gift_nifty_analysis
      when '/oi_snapshot' then oi_snapshot
      when '/market_summary' then market_summary
      when '/expiry_roadmap' then expiry_roadmap
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

    def options_avoid_check
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

    def oi_snapshot
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

    def expiry_roadmap
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

    def instrument_for(symbol, exchange)
      scope = Instrument.where(exchange: exchange)
      scope.find_by(underlying_symbol: symbol) ||
        scope.find_by(symbol_name: symbol) ||
        scope.find_by(trading_symbol: symbol)
    end

    def send_not_implemented(description)
      TelegramNotifier.send_message(
        "⏳ #{description} – not implemented yet.",
        chat_id: @cid
      )
    end
  end
end
