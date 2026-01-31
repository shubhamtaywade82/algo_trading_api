# frozen_string_literal: true

class ApplicationJob < ActiveJob::Base
  before_perform :ensure_dhan_token!

  discard_on Exceptions::DhanTokenExpiredError do |job, _error|
    notify_telegram_if_chat_available(job)
  end

  retry_on StandardError, attempts: 5, wait: :exponentially_longer

  rescue_from(StandardError) do |exception|
    ErrorLogger.log_error('Job failed', exception) unless exception.is_a?(Exceptions::DhanTokenExpiredError)
    raise exception
  end

  private

  def notify_telegram_if_chat_available(job)
    chat_id = job.arguments.first if job.arguments.first.is_a?(Integer)
    return if chat_id.blank?

    TelegramNotifier.send_message(
      '🔐 Dhan session expired. Re-login at /auth/dhan/login to run analysis again.',
      chat_id: chat_id
    )
  rescue StandardError => e
    Rails.logger.warn("[ApplicationJob] Could not notify Telegram on Dhan token discard: #{e.message}")
  end

  def ensure_dhan_token!
    return if DhanAccessToken.valid?

    raise Exceptions::DhanTokenExpiredError
  end
end
