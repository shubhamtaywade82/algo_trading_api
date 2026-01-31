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

  # Telegram inline buttons reject localhost; use only for public HTTPS URLs.
  def self.public_url?(url)
    return false if url.blank?

    uri = URI(url)
    uri.scheme == 'https' && uri.host.present? && !%w[localhost 127.0.0.1].include?(uri.host.downcase)
  rescue URI::InvalidURIError
    false
  end

  #
  # -- PRIVATE --------------------------------------------------------------
  #
  def self.post(method, **params)
    uri = URI("#{TELEGRAM_API}/bot#{ENV.fetch('TELEGRAM_BOT_TOKEN')}/#{method}")
    body = params.transform_keys(&:to_s).to_json
    req = Net::HTTP::Post.new(uri)
    req['Content-Type'] = 'application/json'
    req.body = body
    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }

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
