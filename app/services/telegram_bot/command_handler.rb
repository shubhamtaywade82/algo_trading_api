module TelegramBot
  class CommandHandler < ApplicationService
    def initialize(chat_id:, command:)
      @chat_id = chat_id
      @command = command
    end

    def call
      case @command
      when 'portfolio' then portfolio
      end
    end

    # --------------------------------------------------------------
    private

    def portfolio
      holdings = Dhanhq::API::Portfolio.holdings # correct endpoint
      attach_ltp!(holdings)

      summary = PortfolioInsights::Analyzer.call(dhan_holdings: holdings)
      TelegramNotifier.send_message(summary || '⚠️ Failed to analyse portfolio', chat_id: @chat_id)
    end

    # quick LTP enrichment to make prompts useful
    def attach_ltp!(rows)
      rows.each do |row|
        row['ltp'] = begin
          Dhanhq::API::Market.ltp(row['securityId'])
        rescue StandardError
          nil
        end
      end
    end
  end
end
