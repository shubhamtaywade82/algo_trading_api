class TelegramController < ApplicationController
  def webhook
    payload = params[:message] || params[:edited_message]
    return head :ok unless payload

    chat_id = payload.dig(:chat, :id)
    text    = payload[:text].to_s.strip.downcase

    TelegramBot::CommandHandler.call(chat_id:, command: text)
    head :ok
  end
end
