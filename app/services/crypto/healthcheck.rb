# frozen_string_literal: true

module Crypto
  # Answers one question out loud: **is Binance reachable and actually
  # returning candles?**
  #
  # The scanner is silent by design — it only speaks when a setup clears every
  # gate — and that makes a data outage indistinguishable from a quiet market.
  # A scanner that has been failing to fetch for six hours looks exactly like
  # one that has found nothing worth taking. This closes that hole: the probe
  # is a real fetch, not a ping alone, because a reachable host that returns no
  # candles is still a dead scanner.
  #
  # Notification is on **state change**, never on every probe. The scan job
  # calls this every five minutes; a message each time would be noise nobody
  # reads, and noise nobody reads is the same as no alerting at all. So:
  #
  #   * first ever probe            → announce (there is no previous state)
  #   * ok → down, or down → ok     → announce
  #   * down → down, ok → ok        → log only
  #   * `force: true`               → announce regardless (startup, `crypto:doctor`)
  #
  # State is held in `Rails.cache` as well as in-process, so the scheduled job
  # and the stream runner do not each announce the same recovery from their own
  # process.
  class Healthcheck
    STATE_CACHE_KEY = 'crypto:smc:health:state'
    # Long enough that a healthy scanner does not re-announce on a whim, short
    # enough that a state lost to a cache eviction is re-established the same
    # trading day.
    STATE_TTL = 12.hours

    Result = Struct.new(:ok, :symbol, :price, :candles, :latency_ms, :error, :status,
                        :base_url, :checked_at, keyword_init: true) do
      def ok? = ok == true
      def state = ok? ? :ok : :down
      def restricted_region? = status == 451
    end

    class << self
      # Probe, log, and announce if the state changed.
      #
      # Never raises: a health probe that takes down the caller it was meant to
      # protect is worse than no probe. Every failure becomes a `down` result.
      #
      # @param force [Boolean] announce even when the state has not changed
      # @return [Result]
      def report(force: false, client: nil, symbol: nil)
        result = new(client: client, symbol: symbol).call
        log(result)
        announce(result, force: force)
        result
      rescue StandardError => e
        Rails.logger.error("[Crypto::Health] probe itself failed: #{e.class} - #{e.message}")
        Result.new(ok: false, error: "#{e.class}: #{e.message}", checked_at: Time.current)
      end

      # Probe only — no logging, no Telegram. For callers that want the facts
      # and will decide themselves what to do with them.
      def call(...) = new(...).call

      # Test seam: the in-process half of the state outlives an example.
      def reset!
        @last_state = nil
      end

      attr_reader :last_state

      private

      def log(result)
        if result.ok?
          Rails.logger.info(
            "[Crypto::Health] Binance OK — #{result.symbol} last #{Formatting.price(result.price)}, " \
            "#{result.candles} candles, #{result.latency_ms}ms via #{result.base_url}"
          )
        else
          Rails.logger.error("[Crypto::Health] Binance UNAVAILABLE via #{result.base_url}: #{result.error}")
          Rails.logger.error('[Crypto::Health] HTTP 451 is a geo-block, not a bug — see CRYPTO_BINANCE_BASE') if result.restricted_region?
        end
      end

      def announce(result, force:)
        previous = previous_state
        remember(result.state)

        return if !force && previous == result.state
        return unless Config.health_alerts?

        chat_id = Config.telegram_chat_id
        if chat_id.blank?
          Rails.logger.warn('[Crypto::Health] no Telegram chat configured; state change not announced')
          return
        end

        TelegramNotifier.send_message(message(result, previous: previous), chat_id: chat_id)
      rescue StandardError => e
        Rails.logger.error("[Crypto::Health] could not announce: #{e.class} - #{e.message}")
      end

      def previous_state
        return @last_state if @last_state

        cached = Rails.cache.read(STATE_CACHE_KEY)
        cached&.to_sym
      rescue StandardError => e
        Rails.logger.warn("[Crypto::Health] shared state unavailable: #{e.class} - #{e.message}")
        nil
      end

      def remember(state)
        @last_state = state
        Rails.cache.write(STATE_CACHE_KEY, state.to_s, expires_in: STATE_TTL)
      rescue StandardError => e
        Rails.logger.warn("[Crypto::Health] could not persist state: #{e.class} - #{e.message}")
      end

      def message(result, previous:)
        result.ok? ? up_message(result, previous) : down_message(result)
      end

      def up_message(result, previous)
        header = previous == :down ? '✅ Binance data restored' : '✅ Binance connected'

        [
          header,
          "#{result.symbol} · #{Config::EXECUTION_TIMEFRAME} · last #{Formatting.price(result.price)}\n" \
          "#{result.candles} candles in #{result.latency_ms}ms · #{result.base_url}",
          "Scanning #{Config.symbols.join(', ')} on #{Config::TIMEFRAMES.join('/')}. " \
          'You will hear from the scanner again only when a setup qualifies.'
        ].join("\n\n")
      end

      def down_message(result)
        lines = ['🚨 Binance data unavailable', "#{result.base_url}\n#{result.error}"]

        if result.restricted_region?
          lines << 'HTTP 451 is a geo-block on the egress IP, not a fault in the app. ' \
                   'Run the scanner from a permitted region or point CRYPTO_BINANCE_BASE ' \
                   'at an endpoint that serves it.'
        end

        lines << 'No crypto setups can be detected until this clears.'
        lines.join("\n\n")
      end
    end

    def initialize(client: nil, symbol: nil)
      @client = client || Binance::Client.new
      @symbol = (symbol.presence || Config.symbols.first).to_s.upcase
    end

    # @return [Result]
    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      @client.ping
      rows = @client.klines(symbol: @symbol, interval: Config::EXECUTION_TIMEFRAME, limit: 2)

      return failure('Binance returned no candles', nil, started) if rows.blank?

      success(rows, started)
    rescue Binance::Error => e
      failure(e.message, e.status, started)
    rescue StandardError => e
      failure("#{e.class}: #{e.message}", nil, started)
    end

    private

    def success(rows, started)
      Result.new(
        ok: true, symbol: @symbol, price: rows.last[4].to_f, candles: rows.size,
        latency_ms: elapsed_ms(started), base_url: @client.base_url, checked_at: Time.current
      )
    end

    def failure(error, status, started)
      Result.new(
        ok: false, symbol: @symbol, error: error, status: status,
        latency_ms: elapsed_ms(started), base_url: @client.base_url, checked_at: Time.current
      )
    end

    def elapsed_ms(started)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end
  end
end
