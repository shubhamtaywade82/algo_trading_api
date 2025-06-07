# frozen_string_literal: true

class ApplicationService
  def self.call(...)
    new(...).call
  end

  private

  # Sends a message to Telegram with optional service tag
  #
  # @param message [String] The message to send
  # @param tag [String, nil] Optional short label like 'SL_HIT', 'TP', etc.
  # @return [void]
  def notify(message, tag: nil)
    context = "[#{self.class.name}]"
    final_message = tag.present? ? "#{context} [#{tag}] #{message}" : "#{context} #{message}"
    TelegramNotifier.send_message(final_message)
  rescue StandardError => e
    Rails.logger.error("[ApplicationService] Telegram Notify Failed: #{e.class} - #{e.message}")
  end

  # # Logs an info-level message with class context
  # def log_info(msg)
  #   Rails.logger.info("[#{self.class.name}] #{msg}")
  # end

  # # Logs a warning message with class context
  # def log_warn(msg)
  #   Rails.logger.warn("[#{self.class.name}] #{msg}")
  # end

  # # Logs an error message with class context
  # def log_error(msg)
  #   Rails.logger.error("[#{self.class.name}] #{msg}")
  # end
  # -------- Logging ---------------------------------------------------------
  %i[info warn error debug].each do |lvl|
    define_method(:"log_#{lvl}") { |msg| Rails.logger.send(lvl, "[#{self.class.name}] #{msg}") }
  end
end
