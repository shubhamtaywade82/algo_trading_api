# frozen_string_literal: true

module Market
  # The roster of indices the autonomous scanner watches, and the switches that
  # decide whether a confluence signal on one of them is allowed to trade.
  #
  # This is deliberately a *roster*, not a `Watchlist` record. `Watchlist` /
  # `WatchlistItem` hold the equity universe that `Watchlists::RefreshService`
  # rebuilds from a scan — 120-odd rows that churn daily. The index set is three
  # symbols that change about never, so a table would add a migration, a seed
  # and a failure mode ("scanner traded nothing because the watchlist row was
  # missing") to answer a question a constant answers.
  #
  # Symbols must exist in the index segment of the scrip master, which
  # `db/seeds/index_instruments.csv` carries — see the instrument-master notes
  # in CLAUDE.md. A symbol that does not resolve is skipped and logged rather
  # than raising, so one bad entry in `INDEX_WATCHLIST` cannot stop the others
  # from trading.
  class IndexWatchlist
    DEFAULT_SYMBOLS = %w[NIFTY BANKNIFTY SENSEX].freeze

    # Which exchange each index lists on. Anything absent is assumed NSE, which
    # is right for every index Dhan carries except the BSE pair.
    EXCHANGES = {
      'NIFTY' => :nse,
      'BANKNIFTY' => :nse,
      'FINNIFTY' => :nse,
      'MIDCPNIFTY' => :nse,
      'SENSEX' => :bse,
      'BANKEX' => :bse
    }.freeze

    # Confluence levels in ascending order of conviction. `ConfluenceDetector`
    # emits :medium at |score| >= 5 and :high at |score| >= 8 out of 14.
    LEVEL_RANK = { none: 0, medium: 1, high: 2 }.freeze

    class << self
      # @return [Array<String>] symbols to watch, upper-cased and de-duplicated
      def symbols
        configured = ENV.fetch('INDEX_WATCHLIST', '').to_s.split(',').map { |s| s.strip.upcase }.reject(&:empty?)
        configured.presence&.uniq || DEFAULT_SYMBOLS
      end

      # @param symbol [String]
      # @return [Boolean]
      def include?(symbol)
        symbols.include?(symbol.to_s.upcase)
      end

      # @param symbol [String]
      # @return [Symbol] :nse or :bse
      def exchange_for(symbol)
        EXCHANGES.fetch(symbol.to_s.upcase, :nse)
      end

      # @param symbol [String]
      # @return [Instrument, nil] the index-segment instrument, or nil when the
      #   scrip master has not been seeded for it
      def instrument_for(symbol)
        Instrument.segment_index.find_by(underlying_symbol: symbol.to_s.upcase)
      end

      # @return [Array<Instrument>] every watched index that resolves
      def instruments
        symbols.filter_map do |symbol|
          instrument = instrument_for(symbol)
          Rails.logger.warn("[IndexWatchlist] #{symbol} not found in the index segment; skipping") if instrument.nil?
          instrument
        end
      end

      # The master switch for autonomous trading off this watchlist. Off by
      # default: importing this file must never, on its own, make the app
      # place orders.
      #
      # @return [Boolean]
      def trading_enabled?
        ENV.fetch('INDEX_WATCHLIST_TRADING', 'false').to_s.casecmp('true').zero?
      end

      # Minimum confluence conviction that may trade. Defaults to :high — a
      # :medium signal (5/14) is worth a Telegram message, not capital.
      #
      # @return [Symbol] :medium or :high
      def min_level
        level = ENV.fetch('INDEX_WATCHLIST_MIN_LEVEL', 'high').to_s.downcase.to_sym
        LEVEL_RANK.key?(level) && level != :none ? level : :high
      end

      # @param level [Symbol] the signal's level
      # @return [Boolean] whether it clears {min_level}
      def level_tradable?(level)
        LEVEL_RANK.fetch(level.to_s.to_sym, 0) >= LEVEL_RANK.fetch(min_level)
      end

      # Per-symbol quiet period after a trade fires. `ConfluenceDetector` has
      # its own 45-minute cooldown, but that one is keyed on the *signal* and
      # resets when the process restarts mid-session; this one is keyed on an
      # order actually being placed.
      #
      # @return [ActiveSupport::Duration]
      def cooldown
        ENV.fetch('INDEX_WATCHLIST_COOLDOWN_MINUTES', '30').to_i.clamp(1, 1_440).minutes
      end

      # Hard stop on how many entries the scanner may fire per symbol per day,
      # whatever the signal says. An unattended loop with a broken gate should
      # cost a bounded number of trades, not a session's worth.
      #
      # @return [Integer]
      def max_trades_per_day
        ENV.fetch('INDEX_WATCHLIST_MAX_TRADES_PER_DAY', '3').to_i.clamp(1, 50)
      end

      # How often {Market::AnalysisUpdater} is re-run by `live:paper_engine`.
      # Matches the 5-minute candles the analysis is computed on; a faster loop
      # re-reads the same candle and burns rate limit.
      #
      # @return [Integer] seconds
      def scan_interval
        ENV.fetch('INDEX_WATCHLIST_SCAN_SECONDS', '180').to_i.clamp(30, 3_600)
      end
    end
  end
end
