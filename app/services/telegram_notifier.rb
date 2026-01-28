# frozen_string_literal: true

require 'net/http'
require 'uri'

class TelegramNotifier
  TELEGRAM_API = 'https://api.telegram.org'
  MAX_LEN      = 4000 # keep margin below Telegram's 4096 limit

  # chat_id is OPTIONAL (falls back to ENV)
  def self.send_message(text, chat_id: nil, **extra_params)
    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID')

    chunks(text).each do |chunk|
      post('sendMessage',
           chat_id: chat_id,
           text: chunk,
           **extra_params)
    end
  end

  def self.send_chat_action(action:, chat_id: nil)
    chat_id ||= ENV.fetch('TELEGRAM_CHAT_ID')
    post('sendChatAction', chat_id: chat_id, action: action)
  end

  #
  # -- PRIVATE --------------------------------------------------------------
  #
  def self.post(method, **params)
    uri = URI("#{TELEGRAM_API}/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}/#{method}")
    res = Net::HTTP.post_form(uri, params)

    Rails.logger.error("Telegram #{method} failed: #{res.body}") unless res.is_a?(Net::HTTPSuccess)
    res
  rescue StandardError => e
    Rails.logger.error("Telegram #{method} error: #{e.message}")
  end
  private_class_method :post

  # Split into safe chunks under MAX_LEN
  def self.chunks(text)
    return [] if text.blank?

    # Try splitting on paragraph boundaries first
    lines = text.split("\n")
    chunks = []
    buf = ''

    lines.each do |line|
      if "#{buf}\n#{line}".length > MAX_LEN
        chunks << buf.strip
        buf = line
      else
        buf += "\n#{line}"
      end
    end
    chunks << buf.strip unless buf.empty?

    chunks
  end
  private_class_method :chunks
end
