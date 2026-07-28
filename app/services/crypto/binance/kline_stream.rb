# frozen_string_literal: true

require 'faye/websocket'
require 'eventmachine'
require 'json'

module Crypto
  module Binance
    # Event-driven half of the scanner: a combined Binance kline stream that
    # runs the analysis the moment a candle closes.
    #
    # The scheduled job is a safety net on a fixed cadence; this is the one
    # that matters, because an SMC read is only meaningful on closed candles.
    # Binance marks that explicitly with `k.x`, so nothing here has to guess
    # from timestamps — an in-progress bar is ignored outright, which is also
    # what stops the scanner reacting to a wick that is about to be filled.
    #
    # One socket carries every symbol × timeframe pair. Binance closes a
    # stream after 24 hours by design, so reconnect is a normal event, not an
    # error path.
    class KlineStream
      BASE = 'wss://fstream.binance.com'

      RECONNECT_BASE_DELAY = 2
      RECONNECT_MAX_DELAY  = 60

      # Two timeframes can close on the same second (every 15m, the 5m closes
      # too). Without this, one candle boundary would fire two identical scans.
      DEBOUNCE_SECONDS = 20

      # Safety-net sweep. This app has no scheduler — Solid Queue's recurring
      # tasks need `bin/jobs` running and the deployed adapter is `:async`, and
      # there is no cron service — so the interval scan lives here rather than
      # in a crontab that may not exist. It only fires for a symbol the stream
      # has not already covered, so a healthy socket makes it a no-op.
      SAFETY_SCAN_INTERVAL = 300

      attr_reader :symbols, :timeframes

      def initialize(symbols: nil, timeframes: nil, on_close: nil)
        @symbols    = Array(symbols.presence || Config.symbols).map(&:upcase)
        @timeframes = Array(timeframes.presence || Config.stream_timeframes)
        @on_close   = on_close || method(:default_handler)
        @last_fired = {}
        @attempts   = 0
      end

      # Blocks, running an EventMachine reactor. Intended for a dedicated
      # process (`rails crypto:stream`), never a web request.
      def run
        # Announce before opening the socket. Starting the listener is the one
        # moment an operator is definitely watching, so the confirmation that
        # Binance answered and returned candles is worth sending unconditionally
        # — and a 451 here is answered in seconds rather than discovered hours
        # later through silence.
        Healthcheck.report(force: true)

        EM.run do
          connect
          start_safety_timer
        end
      end

      def stream_url
        streams = symbols.product(timeframes).map { |symbol, tf| "#{symbol.downcase}@kline_#{tf}" }
        "#{BASE}/stream?streams=#{streams.join('/')}"
      end

      private

      def connect
        url = stream_url
        Rails.logger.info("[Crypto::KlineStream] connecting: #{url}")
        socket = Faye::WebSocket::Client.new(url, [], ping: 60)

        socket.on(:open) do
          @attempts = 0
          Rails.logger.info("[Crypto::KlineStream] connected — #{symbols.join(', ')} @ #{timeframes.join(', ')}")
        end

        socket.on(:message) { |event| handle_message(event.data) }
        socket.on(:error)   { |event| Rails.logger.error("[Crypto::KlineStream] error: #{event.message}") }
        socket.on(:close) do |event|
          Rails.logger.warn("[Crypto::KlineStream] closed (#{event.code}) #{event.reason} — reconnecting")
          schedule_reconnect
        end
      end

      # Covers the window where the socket is down, or where Binance stopped
      # publishing without closing the connection. A symbol the stream already
      # scanned inside the interval is skipped.
      def start_safety_timer
        EM.add_periodic_timer(SAFETY_SCAN_INTERVAL) do
          # Off the reactor thread: the probe makes blocking HTTPS calls, and a
          # blocked reactor stops reading frames until it returns.
          EM.defer { Healthcheck.report }

          stale = symbols.reject { |symbol| recently_scanned?(symbol) }
          next if stale.empty?

          Rails.logger.info("[Crypto::KlineStream] safety scan for #{stale.join(', ')}")
          stale.each { |symbol| @on_close.call(symbol, 'safety') }
        end
      end

      def recently_scanned?(symbol)
        last = @last_fired[symbol]
        last.present? && (Time.current - last) < SAFETY_SCAN_INTERVAL
      end

      def schedule_reconnect
        @attempts += 1
        delay = [RECONNECT_BASE_DELAY * (2**(@attempts - 1)), RECONNECT_MAX_DELAY].min
        EM.add_timer(delay) { connect }
      end

      def handle_message(raw)
        payload = JSON.parse(raw)
        kline = payload.dig('data', 'k') || payload['k']
        return if kline.nil?
        return unless kline['x'] # candle still forming

        # Binance repeats the symbol at the event level and inside the kline.
        # Read both: a combined stream nests the event under "data", a raw
        # single stream does not, and only the inner copy is common to both.
        symbol = payload.dig('data', 's') || payload['s'] || kline['s']
        timeframe = kline['i']
        return if symbol.blank?
        return unless fire?(symbol)

        Rails.logger.info("[Crypto::KlineStream] #{symbol} #{timeframe} closed at #{kline['c']} — scanning")
        @on_close.call(symbol, timeframe)
      rescue JSON::ParserError => e
        Rails.logger.error("[Crypto::KlineStream] unparseable frame: #{e.message}")
      rescue StandardError => e
        Rails.logger.error("[Crypto::KlineStream] handler failed: #{e.class} - #{e.message}")
      end

      def fire?(symbol)
        now = Time.current
        last = @last_fired[symbol]
        return false if last && (now - last) < DEBOUNCE_SECONDS

        @last_fired[symbol] = now
        true
      end

      # A scan makes several HTTPS round trips, so it must never run on the
      # reactor thread — a blocked reactor stops reading frames and the socket
      # dies. `EM.defer` hands it to the thread pool; the enqueue mode exists
      # for deployments that would rather the worker do it.
      def default_handler(symbol, _timeframe)
        if enqueue_mode?
          SmcScanJob.perform_later([symbol])
        else
          EM.defer { run_scan(symbol) }
        end
      end

      def run_scan(symbol)
        Scanner.call(symbols: [symbol])
      rescue StandardError => e
        Rails.logger.error("[Crypto::KlineStream] scan failed for #{symbol}: #{e.class} - #{e.message}")
      ensure
        ActiveRecord::Base.connection_handler.clear_active_connections! if defined?(ActiveRecord::Base)
      end

      def enqueue_mode?
        ENV.fetch('CRYPTO_SMC_STREAM_MODE', 'inline').to_s.downcase == 'enqueue'
      end
    end
  end
end
