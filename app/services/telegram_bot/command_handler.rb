module TelegramBot
  class CommandHandler < ApplicationService
    def initialize(chat_id:, command:)
      @cid = chat_id
      @cmd = command
    end

    def call
      case @cmd
      when '/portfolio'  then portfolio_brief
      when '/positions'  then positions_brief
      else TelegramNotifier.send_message("❓ Unknown command: #{@cmd}", chat_id: @cid)
      end
    end

    # --------------------------------------------------------------
    private

    def portfolio_brief
      TelegramNotifier.send_chat_action(chat_id: @cid, action: 'typing')
      holdings = Dhanhq::API::Portfolio.holdings
      result   = PortfolioInsights::Analyzer.call(
                   dhan_holdings: holdings,
                   interactive: true
                 )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    end

    def positions_brief
      TelegramNotifier.send_chat_action(chat_id: @cid, action: 'typing')
      positions = Dhanhq::API::Portfolio.positions
      result    = PositionInsights::Analyzer.call(
                    dhan_positions: positions,
                    interactive: true
                  )
      TelegramNotifier.send_message(result, chat_id: @cid) if result
    end
  end
end
