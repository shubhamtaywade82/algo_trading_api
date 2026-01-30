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
      send_not_implemented('Option buying avoidance (IV/VIX/theta)')
    end

    def gift_nifty_analysis
      send_not_implemented('GIFT Nifty open-gap prediction')
    end

    def oi_snapshot
      send_not_implemented('Option chain OI regime summary')
    end

    def market_summary
      send_not_implemented('Session index + options + VIX summary')
    end

    def expiry_roadmap
      send_not_implemented('Weekly expiry theta/IV roadmap')
    end

    def send_not_implemented(description)
      TelegramNotifier.send_message(
        "⏳ #{description} – not implemented yet.",
        chat_id: @cid
      )
    end
  end
end
