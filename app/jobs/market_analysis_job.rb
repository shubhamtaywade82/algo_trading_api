class MarketAnalysisJob < ApplicationJob
  queue_as :default

  def perform(chat_id, symbol, exchange: :nse, trade_type: nil)
    answer = Market::AnalysisService.call(symbol, exchange: exchange, trade_type: trade_type)
    if answer.present?
      TelegramNotifier.send_message(answer, chat_id: chat_id)
    else
      TelegramNotifier.send_message(no_result_message(symbol, exchange), chat_id: chat_id)
    end
  rescue StandardError => e
    Rails.logger.error "[MarketAnalysisJob] ❌ #{e.class} – #{e.message}"
    Rails.logger.error e.backtrace.first(8).map { |l| "  #{l}" }.join("\n")
    msg = user_facing_error_message(e)
    TelegramNotifier.send_message(msg, chat_id: chat_id)
  end

  private

  # Market::AnalysisService returns nil for three different reasons and "no
  # result" tells the operator which of them to fix: none. The one that
  # actually happens on a fresh database is an instrument master that was never
  # imported — every lookup misses, and the only trace is a log line reading
  # "Instrument not found: NIFTY".
  def no_result_message(symbol, exchange)
    if Instrument.none?
      '📭 The instrument master is empty, so no symbol can be resolved. Run `rails db:seed` for the ' \
        'indices or `rails instruments:import` for the full scrip master, then try again.'
    elsif resolvable?(symbol, exchange)
      "⚠️ Analysis for #{symbol} returned no result. Check data availability and try again."
    else
      "🔍 #{symbol} is not in the instrument master for #{exchange.to_s.upcase}. " \
        'Re-run `rails instruments:import` if the exchange should be listing it.'
    end
  end

  def resolvable?(symbol, exchange)
    Instrument.lookup_by_symbol(
      symbol, exchange: exchange, segment: Market::AnalysisService::DEFAULT_SEGMENT
    ).present?
  end

  def user_facing_error_message(e)
    return '🔐 Dhan session or data access issue. Refresh your token or subscribe to Data APIs, then try again.' if dhan_related_error?(e)
    return '⚠️ Analysis service unavailable (connection error). Try again in a moment.' if connection_error?(e)

    "🚨 Error running analysis – #{e.message}"
  end

  def connection_error?(e)
    return true if e.is_a?(Faraday::ConnectionFailed)
    return true if e.is_a?(Faraday::TimeoutError)

    name = e.class.name.to_s
    name.include?('ConnectionFailed') || name.include?('TimeoutError') || name.include?('EOFError')
  end

  def dhan_related_error?(e)
    name = e.class.name.to_s
    msg  = e.message.to_s
    name.include?('Authentication') || name.include?('Unauthorized') || msg.include?('401') || msg.include?('451') || msg.include?('DH-902')
  end
end