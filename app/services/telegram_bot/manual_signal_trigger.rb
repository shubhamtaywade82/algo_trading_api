# frozen_string_literal: true

require 'securerandom'

module TelegramBot
  # ManualSignalTrigger allows triggering the existing index alert pipeline from
  # Telegram commands (e.g. "nifty ce" / "banknifty pe"). It creates a minimal
  # Alert record that mimics the TradingView payload and then hands it off to the
  # regular AlertProcessor.
  class ManualSignalTrigger < ApplicationService
    def initialize(chat_id:, symbol:, option:, exchange: :nse)
      @chat_id = chat_id
      @symbol = symbol.to_s.upcase
      @option = option.to_sym
      @exchange = exchange.to_sym
    end

    def call
      TelegramNotifier.send_chat_action(chat_id: @chat_id, action: 'typing')

      instrument = find_instrument!
      alert = create_alert!(instrument)

      AlertProcessorFactory.build(alert).call

      TelegramNotifier.send_message(success_message(alert), chat_id: @chat_id)

      alert
    rescue ActiveRecord::RecordNotFound => e
      log_error("Instrument lookup failed for #{@symbol}: #{e.message}")
      TelegramNotifier.send_message(
        "⚠️ Unable to trigger #{@symbol} #{@option.to_s.upcase} – instrument not configured.",
        chat_id: @chat_id
      )
      nil
    rescue StandardError => e
      log_error("Manual signal failed – #{e.class}: #{e.message}")
      TelegramNotifier.send_message(
        "🚨 Manual signal for #{@symbol} #{@option.to_s.upcase} failed – #{e.message}",
        chat_id: @chat_id
      )
      nil
    end

    private

    def find_instrument!
      Instrument
        .where('LOWER(underlying_symbol) = ?', @symbol.downcase)
        .where(exchange: @exchange)
        .where(segment: :index)
        .first!
    end

    def create_alert!(instrument)
      instrument.alerts.create!(base_alert_attributes(instrument))
    end

    def base_alert_attributes(instrument)
      {
        ticker: @symbol,
        instrument_type: 'index',
        exchange: exchange_code.upcase,
        order_type: 'market',
        action: 'buy',
        signal_type: signal_type,
        strategy_type: 'intraday',
        strategy_name: 'Manual Telegram Signal',
        strategy_id: SecureRandom.uuid,
        current_position: 'flat',
        previous_position: 'flat',
        current_price: fetch_current_price(instrument),
        chart_interval: 'manual',
        time: Time.zone.now.iso8601,
        metadata: {
          'triggered_by' => 'telegram_manual',
          'option_type' => @option.to_s.upcase
        }
      }
    end

    def fetch_current_price(instrument)
      price = instrument.quote_ltp || instrument.ltp
      price.present? ? price.to_f : 0.0
    rescue StandardError
      0.0
    end

    def signal_type
      @option == :ce ? 'long_entry' : 'short_entry'
    end

    def exchange_code
      @exchange.to_s.downcase
    end

    def success_message(alert)
      "✅ Manual #{@symbol} #{@option.to_s.upcase} signal queued.\nAlert ##{alert.id} is being processed."
    end
  end
end
