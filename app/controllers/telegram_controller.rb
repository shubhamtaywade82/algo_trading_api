class TelegramController < ApplicationController
  def webhook
    pp params
    payload = params[:message] || params[:edited_message]
    return head :ok unless payload

    chat_id = payload.dig(:chat, :id)
    text    = payload[:text].to_s.strip.downcase

    case text
    when '/portfolio'
      TelegramBot::CommandHandler.call(chat_id: chat_id, command: 'portfolio')
    else
      TelegramNotifier.send_message("❓ Unknown command: #{text}", chat_id: chat_id)
    end

    head :ok
  end
end
