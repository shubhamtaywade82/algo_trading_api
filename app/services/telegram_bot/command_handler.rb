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
      # Add these to your case statement in call method
      when '/nifty_options' then run_options_buying_analysis('NIFTY')
      when '/banknifty_options' then run_options_buying_analysis('BANKNIFTY')
      when '/sensex_options' then run_options_buying_analysis('SENSEX', exchange: :bse)
      else
        handled = try_manual_signal!
        TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid) unless handled
      end
    end

    # --------------------------------------------------------------
    private

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
      result   = PortfolioInsights::Analyzer.call(
                   dhan_holdings: holdings,
                   interactive: true
                 )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: @cid)
    end

    # Add to your TelegramBot::CommandHandler
    def run_options_buying_analysis(symbol, exchange: :nse)
      typing_ping
  
      # Call with options_buying trade_type
      MarketAnalysisJob.perform_later(@cid, symbol, exchange: exchange, trade_type: :options_buying)
      #analysis = Market::AnalysisService.new(
      #   symbol, 
      #   exchange: exchange, 
      #   trade_type: :options_buying
      #).call
  
      #if analysis.present?
      TelegramNotifier.send_message("🎯 **#{symbol} Options Buying Setup**", chat_id: @cid)
      #else
      #  TelegramNotifier.send_message("⚠️ Couldn't generate options setup for #{symbol}.", chat_id: @cid)
      #end
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      TelegramNotifier.send_message("🚨 Error generating options setup – #{e.message}", chat_id: @cid)
    end

    # 4️⃣ — NEW  market-analysis hook
    def run_market_analysis(symbol, exchange: :nse)
      typing_ping

      # Instead of calling the service directly, enqueue a job
      MarketAnalysisJob.perform_later(@cid, symbol, exchange: exchange)

      # Immediately return — don’t block here
      TelegramNotifier.send_message("📊 Analysis started for #{symbol}. You'll get a detailed report shortly.", chat_id: @cid)

      # Market::AnalysisService.call(symbol, exchange: exchange)
      # # if analysis.present?
      # #   TelegramNotifier.send_message("📊 *#{symbol} Analysis completed.*", chat_id: @cid)
      # # else
      # #   TelegramNotifier.send_message("⚠️ Couldn’t complete analysis for #{symbol}.", chat_id: @cid)
      # # end
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: @cid)
    end

    def institutional_portfolio_brief
      # ── Throttle: run max once per UTC-day ───────────────────────────
      # last_run = Rails.cache.read(ANALYSIS_CACHE_KEY)
      # if last_run&.to_date == Time.now.utc.to_date
      #   TelegramNotifier.send_message("⚠️ Full analysis already generated today.\nUse /portfolio for a quick view.", chat_id: @cid)
      #   return
      # end

      typing_ping

      holdings = Dhanhq::API::Portfolio.holdings
      unless holdings
        return TelegramNotifier.send_message("⚠️ Full analysis already generated today.\nUse /portfolio for a quick view.",
                                             chat_id: @cid)
      end

      balance   = Dhanhq::API::Funds.balance
      positions = Dhanhq::API::Portfolio.positions

      result = PortfolioInsights::InstitutionalAnalyzer.call(
                 dhan_holdings: holdings,
                 dhan_positions: positions,
                 dhan_balance: balance,
                 interactive: true
               )

      return unless result

      Rails.cache.write(ANALYSIS_CACHE_KEY, Time.now.utc, expires_in: 25.hours)
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: @cid)
    end

    def positions_brief
      typing_ping
      positions = Dhanhq::API::Portfolio.positions

      PositionInsights::Analyzer.call(
                  dhan_positions: positions,
                  interactive: true
                )
    rescue StandardError => e
      Rails.logger.error "[CommandHandler] ❌ #{e.class} – #{e.message}"
      TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: @cid)
    end
  end
end
