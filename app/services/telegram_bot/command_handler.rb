module TelegramBot
  class CommandHandler < ApplicationService
    ANALYSIS_CACHE_KEY = 'portfolio:institutional:last_run'.freeze

    def initialize(chat_id:, command:)
      @cid = chat_id
      @cmd = command
    end

    def call
      case @cmd
      when '/portfolio'  then quick_portfolio_brief
      when '/positions'  then positions_brief
      when '/portfolio_full'  then institutional_portfolio_brief
      else TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid)
      end
    end

    # --------------------------------------------------------------
    private

    def quick_portfolio_brief
      TelegramNotifier.send_chat_action(chat_id: @cid, action: 'typing')
      holdings = Dhanhq::API::Portfolio.holdings
      result   = PortfolioInsights::Analyzer.call(
                   dhan_holdings: holdings,
                   interactive: true
                 )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    end

    def institutional_portfolio_brief
      # ── Throttle: run max once per UTC-day ───────────────────────────
      # last_run = Rails.cache.read(ANALYSIS_CACHE_KEY)
      # if last_run&.to_date == Time.now.utc.to_date
      #   TelegramNotifier.send_message("⚠️ Full analysis already generated today.\nUse /portfolio for a quick view.", chat_id: @cid)
      #   return
      # end

      TelegramNotifier.send_chat_action(chat_id: @cid, action: 'typing')

      holdings  = Dhanhq::API::Portfolio.holdings
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
    end

    def positions_brief
      TelegramNotifier.send_chat_action(chat_id: @cid, action: 'typing')
      positions = Dhanhq::API::Portfolio.positions

      PositionInsights::Analyzer.call(
                  dhan_positions: positions,
                  interactive: true
                )
    end
  end
end
