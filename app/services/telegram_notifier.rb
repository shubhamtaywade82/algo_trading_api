# frozen_string_literal: true

require 'net/http'
require 'uri'

class TelegramNotifier
  TELEGRAM_API = 'https://api.telegram.org'

  def self.send_message(text, chat_id:)
    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID')
    post('sendMessage', chat_id:, text:)
  end

  def self.send_chat_action(chat_id, action)
    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID')
    post('sendChatAction', chat_id:, action:)
  end

  def self.post(method, **params)
    uri  = URI("#{TELEGRAM_API}/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}/#{method}")
    res  = Net::HTTP.post_form(uri, params)
    Rails.logger.error("Telegram #{method} failed: #{res.body}") unless res.is_a?(Net::HTTPSuccess)
    res
  rescue StandardError => e
    Rails.logger.error("Telegram error: #{e.message}")
  end
end
