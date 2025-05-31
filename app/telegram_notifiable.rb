module TelegramNotifiable
  extend ActiveSupport::Concern

  private

  def notify_telegram(text)
    return unless ActiveModel::Type::Boolean.new.cast(
                   ENV.fetch("TELEGRAM_NOTIF_ENABLED", "false")
                 )

    TelegramNotifier.send_message(text)
  end
end