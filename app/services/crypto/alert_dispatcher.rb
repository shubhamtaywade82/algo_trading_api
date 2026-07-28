# frozen_string_literal: true

module Crypto
  # Sends a {Setup} to Telegram, once.
  #
  # The whole point of the scanner is that it only speaks when there is
  # something to say, so suppression is as much a feature as sending. Two
  # layers do it, because two different processes dispatch:
  #
  #   * an in-process hash — free, and enough for repeated scans in one worker
  #   * `Rails.cache` — shared, so the scheduled job and the event-driven
  #     stream runner do not both announce the same setup from their own
  #     processes seconds apart
  #
  # The cache entry is a short-lived mutex keyed on the setup's identity, not
  # a record of the analysis: nothing about the setup is stored, and the key
  # expires with the cooldown.
  class AlertDispatcher
    class << self
      # @return [Symbol] :sent, :suppressed, :unconfigured or :failed
      def dispatch(setup)
        return :unconfigured if chat_id.blank?
        return :suppressed if recent?(setup.dedupe_key)

        remember(setup.dedupe_key)
        deliver(setup)
      end

      # Test seam — the in-process half of the cooldown outlives an example
      # otherwise, since it is deliberately class-level state.
      def reset!
        mutex.synchronize { store.clear }
      end

      private

      def deliver(setup)
        TelegramNotifier.send_message(SetupFormatter.call(setup), chat_id: chat_id)
        Rails.logger.info("[Crypto] alerted #{setup.symbol} #{setup.side} score=#{setup.score} rr=#{setup.risk_reward}")
        :sent
      rescue StandardError => e
        Rails.logger.error("[Crypto] Telegram dispatch failed for #{setup.symbol}: #{e.class} - #{e.message}")
        :failed
      end

      def recent?(key)
        return true if in_process_recent?(key)

        shared_recent?(key)
      end

      def in_process_recent?(key)
        mutex.synchronize do
          expiry = store[key]
          next false if expiry.nil?
          next true if expiry > Time.current

          store.delete(key)
          false
        end
      end

      def shared_recent?(key)
        Rails.cache.read(cache_key(key)).present?
      rescue StandardError => e
        Rails.logger.warn("[Crypto] shared cooldown unavailable: #{e.class} - #{e.message}")
        false
      end

      def remember(key)
        cooldown = Config.cooldown_seconds
        mutex.synchronize do
          purge_expired
          store[key] = Time.current + cooldown
        end

        begin
          Rails.cache.write(cache_key(key), true, expires_in: cooldown)
        rescue StandardError => e
          Rails.logger.warn("[Crypto] could not write shared cooldown: #{e.class} - #{e.message}")
        end
      end

      # Called under the mutex.
      def purge_expired
        now = Time.current
        store.delete_if { |_, expiry| expiry <= now }
      end

      def cache_key(key) = "crypto:smc:alert:#{key}"

      def chat_id = Config.telegram_chat_id

      def store
        @store ||= {}
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end
  end
end
