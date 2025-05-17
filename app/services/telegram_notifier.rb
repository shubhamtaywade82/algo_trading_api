require 'net/http'
require 'uri'

class TelegramNotifier
  TELEGRAM_API = 'https://api.telegram.org'.freeze

  def self.send_message(text)
    token = ENV.fetch('TELEGRAM_BOT_TOKEN')
    chat_id = ENV.fetch('TELEGRAM_CHAT_ID')

    uri = URI("#{TELEGRAM_API}/bot#{token}/sendMessage")
    res = Net::HTTP.post_form(uri, chat_id: chat_id, text: text)

    Rails.logger.error("Telegram message failed: #{res.body}") unless res.is_a?(Net::HTTPSuccess)
  rescue KeyError => e
    Rails.logger.error("Environment variable missing: #{e.message}")
  rescue StandardError => e
    Rails.logger.error("Error sending Telegram message: #{e.message}")
  end
end
