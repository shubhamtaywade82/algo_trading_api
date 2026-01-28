class MarketAnalysisJob < ApplicationJob
  queue_as :default

  def perform(chat_id, symbol, exchange: :nse, trade_type: nil)
    answer = Market::AnalysisService.call(symbol, exchange: exchange, trade_type: trade_type)
    if answer.present?
      TelegramNotifier.send_message(answer, chat_id: chat_id)
    else
      TelegramNotifier.send_message(
        "⚠️ Analysis for #{symbol} could not be completed. Check Dhan Data API subscription and session, then try again.",
        chat_id: chat_id
      )
    end
  rescue StandardError => e
    Rails.logger.error "[MarketAnalysisJob] ❌ #{e.class} – #{e.message}"
    msg = dhan_related_error?(e) ? '🔐 Dhan session or data access issue. Refresh your token or subscribe to Data APIs, then try again.' : "🚨 Error running analysis – #{e.message}"
    TelegramNotifier.send_message(msg, chat_id: chat_id)
  end

  private

  def dhan_related_error?(e)
    name = e.class.name.to_s
    msg  = e.message.to_s
    name.include?('Authentication') || name.include?('Unauthorized') || msg.include?('401') || msg.include?('451') || msg.include?('DH-902')
  end
end