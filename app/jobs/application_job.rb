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

    url_opts = Rails.application.config.action_controller.default_url_options || {}
    login_url = url_opts[:host].present? ? Rails.application.routes.url_helpers.auth_dhan_login_url(url_opts) : nil
    text = login_url ? "🔐 Dhan session expired. [Re-login here](#{login_url}) to run analysis again." : '🔐 Dhan session expired. Re-login at /auth/dhan/login to run analysis again.'
    opts = { chat_id: chat_id, parse_mode: 'Markdown' }
    if login_url.present? && TelegramNotifier.public_url?(login_url)
      opts[:reply_markup] =
        { inline_keyboard: [[{ text: 'Re-login', url: login_url }]] }
    end
    TelegramNotifier.send_message(text, **opts)
  rescue StandardError => e
    Rails.logger.warn("[ApplicationJob] Could not notify Telegram on Dhan token discard: #{e.message}")
  end

  def ensure_dhan_token!
    return if DhanAccessToken.valid?

    raise Exceptions::DhanTokenExpiredError
  end
end
