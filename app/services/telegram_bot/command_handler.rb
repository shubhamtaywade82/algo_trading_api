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
      when '/nifty_analysis' then run_market_analysis('NIFTY')
      when '/sensex_analysis' then run_market_analysis('SENSEX', exchange: :bse)
      when '/bank_nifty_analysis' then run_market_analysis('BANKNIFTY')
      when '/stocks_screener' then run_stocks_screener
      else TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid)
      end
    end

    # --------------------------------------------------------------
    private

    def quick_portfolio_brief
      typing_ping
      holdings = Dhanhq::API::Portfolio.holdings
      result   = PortfolioInsights::Analyzer.call(
                   dhan_holdings: holdings,
                   interactive: true
                 )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    end

    # 4️⃣ — NEW  market-analysis hook
    def run_market_analysis(symbol, exchange: :nse)
      typing_ping

      Market::AnalysisService.call(symbol, exchange: exchange)
      # if analysis.present?
      #   TelegramNotifier.send_message("📊 *#{symbol} Analysis completed.*", chat_id: @cid)
      # else
      #   TelegramNotifier.send_message("⚠️ Couldn’t complete analysis for #{symbol}.", chat_id: @cid)
      # end
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

      PositionInsights::Analyzer.call(
                  dhan_positions: positions,
                  interactive: true
                )
    end
  end
end
