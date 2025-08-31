class MarketAnalysisJob < ApplicationJob
  queue_as :default

  def perform(chat_id, symbol, exchange: :nse)
    answer = Market::AnalysisService.call(symbol, exchange: exchange)
    TelegramNotifier.send_message(answer, chat_id: chat_id) if answer.present?
  rescue StandardError => e
    Rails.logger.error "[MarketAnalysisJob] ❌ #{e.class} – #{e.message}"
    TelegramNotifier.send_message("🚨 Error running analysis – #{e.message}", chat_id: chat_id)
  end
end