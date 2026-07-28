# frozen_string_literal: true

module Crypto
  # Every knob the SMC scanner reads, in one place.
  #
  # This module is deliberately env-driven and stateless: the scanner persists
  # nothing, so configuration is the only state it has. Defaults are the ones
  # the desk actually runs with — SOLUSDT and ETHUSDT on Binance USD-M futures,
  # analysed top-down on 1d/4h/1h/15m with 5m as the execution timeframe.
  module Config
    # Analysis timeframes, highest first. The last entry is the execution
    # timeframe and is treated specially by SetupDetector: a setup is never
    # emitted without a trigger on it.
    HTF_TIMEFRAMES       = %w[1d 4h].freeze
    STRUCTURE_TIMEFRAME  = '1h'
    SETUP_TIMEFRAME      = '15m'
    EXECUTION_TIMEFRAME  = '5m'

    TIMEFRAMES = [*HTF_TIMEFRAMES, STRUCTURE_TIMEFRAME, SETUP_TIMEFRAME, EXECUTION_TIMEFRAME].freeze

    # How many candles to pull per timeframe. Enough history for structure to
    # have several swings to work with, not so much that a scan is slow.
    CANDLE_LIMITS = {
      '1d' => 180,
      '4h' => 250,
      '1h' => 300,
      '15m' => 300,
      '5m' => 300
    }.freeze

    DEFAULT_SYMBOLS = %w[SOLUSDT ETHUSDT].freeze

    module_function

    # Master switch. The scanner is opt-in so that adding it to this app
    # changes nothing about an existing DhanHQ deployment until asked.
    def enabled?
      ENV.fetch('CRYPTO_SMC_ENABLED', 'false').to_s.downcase == 'true'
    end

    # @return [Array<String>] uppercased Binance symbols, e.g. ["SOLUSDT"]
    def symbols
      raw = ENV.fetch('CRYPTO_SMC_SYMBOLS', '').to_s
      list = raw.split(',').map { |s| s.strip.upcase }.reject(&:empty?)
      list.presence || DEFAULT_SYMBOLS
    end

    # Confluence score (0-100) a candidate must reach to be alerted.
    def min_score
      ENV.fetch('CRYPTO_SMC_MIN_SCORE', '62').to_f
    end

    # Minimum reward:risk to the first target. Below this the setup is real
    # but not worth taking, and an alert would be noise.
    def min_risk_reward
      ENV.fetch('CRYPTO_SMC_MIN_RR', '1.8').to_f
    end

    # Silence window per symbol+direction. Structure does not change every
    # five minutes; without this the same setup re-alerts on every scan.
    def cooldown_seconds
      ENV.fetch('CRYPTO_SMC_COOLDOWN_MINUTES', '45').to_f * 60
    end

    # Widest stop we will publish, as a multiple of the 15m ATR. A stop beyond
    # this means the POI is stale and the entry has already run away.
    def max_stop_atr_multiple
      ENV.fetch('CRYPTO_SMC_MAX_STOP_ATR', '2.5').to_f
    end

    # Fractal width for swing detection: a pivot needs this many bars either
    # side. 2 is the ICT standard three-bar-plus fractal.
    def swing_strength
      ENV.fetch('CRYPTO_SMC_SWING_STRENGTH', '2').to_i
    end

    def telegram_chat_id
      ENV['CRYPTO_TELEGRAM_CHAT_ID'].presence || ENV.fetch('TELEGRAM_CHAT_ID', nil)
    end

    # Streams the event-based runner subscribes to. Only closed candles on
    # these timeframes trigger a scan; 1h/4h/1d closes are covered by the
    # scheduled scan.
    def stream_timeframes
      raw = ENV.fetch('CRYPTO_SMC_STREAM_TIMEFRAMES', '5m,15m').to_s
      list = raw.split(',').map { |s| s.strip.downcase }.reject(&:empty?)
      list.presence || %w[5m 15m]
    end
  end
end
