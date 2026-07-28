# frozen_string_literal: true

require 'securerandom'

module Market
  # Turns a {Market::ConfluenceDetector::ConfluenceSignal} into a tradable
  # signal on the existing pipeline.
  #
  # This is a signal *source*, not a second execution path. It builds an Alert
  # and hands it to `AlertProcessorFactory`, exactly as the TradingView webhook
  # and {TelegramBot::ManualSignalTrigger} do, so strike selection, sizing,
  # risk and placement all stay in `AlertProcessors::Index` →
  # `Orders::Gateway`. Nothing here talks to a broker or to `Paper::Exchange`;
  # whether the resulting order is simulated is the gateway's decision, made
  # from `PAPER_TRADING`.
  #
  # ## Gates, in the order they are applied
  #
  # 1. `INDEX_WATCHLIST_TRADING` — off by default.
  # 2. The symbol is on {Market::IndexWatchlist}.
  # 3. The signal clears `INDEX_WATCHLIST_MIN_LEVEL` (default :high, 8/14).
  # 4. It is a trading day and we are inside the entry window.
  # 5. No trade on this symbol within `INDEX_WATCHLIST_COOLDOWN_MINUTES`.
  # 6. Today's entries for this symbol are under
  #    `INDEX_WATCHLIST_MAX_TRADES_PER_DAY`.
  #
  # Gates 5 and 6 are belt and braces over `ConfluenceDetector`'s own
  # state-change and cooldown logic, which is keyed on the signal rather than
  # on an order: a process restart repopulates its cache from scratch, and a
  # detector that started flip-flopping would otherwise trade every flip.
  class ConfluenceTrader < ApplicationService
    STRATEGY_NAME = 'Index Confluence Scanner'
    ZONE = 'Asia/Kolkata'

    # No entries in the first minutes — the opening range is noise and the
    # 5-minute candles the score is computed on have barely formed.
    ENTRY_OPENS_AT = { hour: 9, min: 20 }.freeze
    # Nothing new after this: Paper::EodSquareOff (and the broker, live) closes
    # INTRADAY at 15:15, so a later entry buys a position to be closed at once.
    ENTRY_CLOSES_AT = { hour: 15, min: 0 }.freeze

    # A bullish score buys a Call, a bearish one buys a Put — the mapping
    # AlertProcessors::Index::SIGNAL_TO_OPTION expects.
    BIAS_TO_SIGNAL = { bullish: 'long_entry', bearish: 'short_entry' }.freeze

    def initialize(signal:)
      @signal = signal
    end

    # @return [Alert, nil] the alert that was processed, or nil when a gate
    #   declined the signal
    def call
      return nil if @signal.nil?
      return nil unless tradable?

      instrument = IndexWatchlist.instrument_for(symbol)
      return log_skip('instrument not found in the index segment') if instrument.nil?

      alert = create_alert!(instrument)
      log_info("#{symbol} #{@signal.bias} #{@signal.level} (#{@signal.net_score}/#{@signal.max_score}) " \
               "→ alert ##{alert.id} #{signal_type}")

      AlertProcessorFactory.build(alert).call
      mark_traded
      alert
    rescue StandardError => e
      log_error("#{symbol} – #{e.class}: #{e.message}")
      nil
    end

    private

    def symbol
      @symbol ||= @signal.symbol.to_s.upcase
    end

    def signal_type
      BIAS_TO_SIGNAL[@signal.bias.to_s.to_sym]
    end

    # ── Gates ────────────────────────────────────────────────────────────────

    def tradable?
      return log_skip('INDEX_WATCHLIST_TRADING is off') unless IndexWatchlist.trading_enabled?
      return log_skip('not on the index watchlist') unless IndexWatchlist.include?(symbol)
      return log_skip("bias #{@signal.bias} is not tradable") if signal_type.nil?
      return log_skip("level #{@signal.level} below #{IndexWatchlist.min_level}") unless level_ok?
      return log_skip('outside the entry window') unless within_entry_window?
      return log_skip('cooling down since the last entry') if cooldown_active?
      return log_skip("daily cap of #{IndexWatchlist.max_trades_per_day} reached") if daily_cap_reached?

      true
    end

    def level_ok?
      IndexWatchlist.level_tradable?(@signal.level)
    end

    # Two conditions, not one. `MarketCalendar.market_open?` is the session
    # itself — weekday, not a listed holiday, 09:15–15:30 IST — and the entry
    # window is a strictly narrower slice of it. Checking both means a change
    # to the session definition can never let an entry fall outside it.
    def within_entry_window?
      now = Time.current.in_time_zone(ZONE)
      return false unless MarketCalendar.market_open?(now)

      now.between?(now.change(**ENTRY_OPENS_AT), now.change(**ENTRY_CLOSES_AT))
    end

    def cooldown_active?
      Rails.cache.read(cooldown_key).present?
    end

    def mark_traded
      Rails.cache.write(cooldown_key, Time.current.iso8601, expires_in: IndexWatchlist.cooldown)
    end

    def cooldown_key
      "index_watchlist:last_trade:#{symbol}"
    end

    # Counts entries this scanner actually put into the pipeline today. A
    # `skipped` alert never reached the broker — the processor declined it on
    # its own analysis — so it does not consume the day's budget, and a
    # `failed` one placed nothing either.
    def daily_cap_reached?
      todays_trades = Alert.where(ticker: symbol, strategy_name: STRATEGY_NAME)
        .where(created_at: Time.current.in_time_zone(ZONE).all_day)
        .where.not(status: %w[skipped failed])
        .count

      todays_trades >= IndexWatchlist.max_trades_per_day
    end

    # ── Alert construction ───────────────────────────────────────────────────

    def create_alert!(instrument)
      instrument.alerts.create!(
        ticker: symbol,
        instrument_type: 'index',
        exchange: IndexWatchlist.exchange_for(symbol).to_s.upcase,
        order_type: 'market',
        action: 'buy',
        signal_type: signal_type,
        strategy_type: 'intraday',
        strategy_name: STRATEGY_NAME,
        strategy_id: SecureRandom.uuid,
        current_position: 'flat',
        previous_position: 'flat',
        current_price: entry_price(instrument),
        chart_interval: '5',
        time: Time.current.iso8601,
        metadata: signal_metadata
      )
    end

    # The signal's own close is the price the score was computed on, which is
    # the honest record of why the trade fired. It is a spot index level, not
    # an option premium — `AlertProcessors::Index` prices the contract itself.
    def entry_price(instrument)
      price = @signal.close.to_f
      return price if price.positive?

      instrument.ltp.to_f
    rescue StandardError
      0.0
    end

    def signal_metadata
      {
        'triggered_by' => 'index_confluence_scanner',
        'bias' => @signal.bias.to_s,
        'level' => @signal.level.to_s,
        'net_score' => @signal.net_score,
        'max_score' => @signal.max_score,
        'atr' => @signal.atr&.round(2),
        'factors' => Array(@signal.factors).map { |f| { 'name' => f.name, 'value' => f.value, 'note' => f.note } }
      }
    end

    # Gates return nil through this so `tradable?` reads as a list of reasons.
    def log_skip(reason)
      log_info("#{symbol} signal not traded – #{reason}")
      nil
    end
  end
end
