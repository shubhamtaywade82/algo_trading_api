# frozen_string_literal: true

module Trading
  # Orchestrates the full intraday trade decision pipeline.
  # Returns a deterministic TRADE or NO_TRADE result.
  # Symbols: NIFTY (NSE index), BANKNIFTY (NSE index), SENSEX (BSE index).
  class TradeDecisionEngine < ApplicationService
    ALLOWED_SYMBOLS = %w[NIFTY SENSEX BANKNIFTY].freeze

    Result = Struct.new(
      :proceed, :symbol, :direction, :expiry,
      :selected_strike, :iv_rank, :regime,
      :chain_analysis, :spot, :reason, :timestamp,
      keyword_init: true
    )

    def initialize(symbol:, expiry: nil)
      @symbol = symbol.to_s.upcase
      @expiry = expiry
    end

    def call
      return no_trade("Symbol #{@symbol} not supported. Use: #{ALLOWED_SYMBOLS.join(', ')}") unless ALLOWED_SYMBOLS.include?(@symbol)

      instrument = resolve_instrument
      return no_trade("Instrument not found for #{@symbol}") unless instrument

      candles = fetch_candles(instrument)
      return no_trade("Insufficient candle data (#{candles.size} candles)") if candles.size < 10

      spot = instrument.ltp.to_f
      return no_trade('LTP unavailable (market may be closed)') if spot.zero?

      expiry_to_use = @expiry.presence || instrument.expiry_list&.first
      return no_trade('No expiry available') unless expiry_to_use

      chain = instrument.fetch_option_chain(expiry_to_use)
      return no_trade('Option chain unavailable') if chain.blank?

      oc = chain[:oc] || chain['oc']
      return no_trade('Option chain OC data empty') if oc.blank?

      iv_rank_raw = Option::ChainAnalyzer.estimate_iv_rank(chain)

      # Context accumulated as each stage passes, so every early return reports
      # everything known at that point.
      ctx = { symbol: @symbol, expiry: expiry_to_use, iv_rank: (iv_rank_raw.to_f * 100).round(1), spot: spot }

      regime = Trading::RegimeScorer.call(spot: spot, candles: candles, iv_rank: ctx[:iv_rank])
      ctx[:regime] = regime
      return no_trade_with(regime.reason, **ctx) if regime.state == :no_trade

      dir_result = Trading::DirectionResolver.call(spot: spot, candles: candles, option_chain: chain)
      return no_trade_with("No directional signal: #{dir_result.reason}", **ctx) unless dir_result.direction

      ctx[:direction] = dir_result.direction

      entry_check = Trading::EntryValidator.call(direction: ctx[:direction], candles: candles)
      return no_trade_with("Entry not confirmed: #{entry_check.reason}", **ctx) unless entry_check.valid

      analysis = analyze_chain(instrument, chain, ctx, iv_rank_raw)
      ctx[:chain_analysis] = safe_chain_analysis(analysis)
      return no_trade_with("Chain analysis blocked: #{analysis[:reason]}", **ctx) unless analysis[:proceed]

      Result.new(
        proceed: true,
        selected_strike: analysis[:selected],
        reason: nil,
        timestamp: Time.current,
        **ctx
      )
    rescue StandardError => e
      Rails.logger.error("[TradeDecisionEngine] #{@symbol}: #{e.message}\n#{e.backtrace&.first(3)&.join("\n")}")
      no_trade("Internal error: #{e.message}")
    end

    private

    def analyze_chain(instrument, chain, ctx, iv_rank_raw)
      historical = Option::HistoricalDataFetcher.for_strategy(instrument, strategy_type: 'intraday')
      analyzer = Option::ChainAnalyzer.new(
        chain,
        expiry: ctx[:expiry],
        underlying_spot: ctx[:spot],
        iv_rank: iv_rank_raw,
        historical_data: historical
      )

      analyzer.analyze(signal_type: ctx[:direction].downcase.to_sym, strategy_type: 'intraday')
    end

    def resolve_instrument
      if @symbol == 'SENSEX'
        Instrument.segment_index.find_by(underlying_symbol: 'SENSEX', exchange: 'bse')
      else
        Instrument.segment_index.find_by(underlying_symbol: @symbol, exchange: 'nse')
      end
    end

    def fetch_candles(instrument)
      raw = instrument.intraday_ohlc(interval: '5', days: 2)
      normalize_candles(raw)
    end

    def normalize_candles(raw)
      return [] if raw.blank?

      # Handle both array and hash response shapes from DhanHQ
      data = raw.is_a?(Array) ? raw : (raw[:data] || raw['data'] || raw[:candles] || raw['candles'] || [])

      data.map do |c|
        c = c.with_indifferent_access
        {
          open: c[:open].to_f,
          high: c[:high].to_f,
          low: c[:low].to_f,
          close: c[:close].to_f,
          volume: c[:volume].to_f
        }
      end.select { |c| c[:close].positive? }
    end

    def safe_chain_analysis(analysis)
      return {} unless analysis.is_a?(Hash)

      analysis.slice(:trend, :momentum, :adx, :reason).merge(
        ranked: Array(analysis[:ranked]).first(3)
      )
    end

    def no_trade(reason)
      Result.new(
        proceed: false,
        symbol: @symbol,
        direction: nil,
        expiry: @expiry,
        selected_strike: nil,
        iv_rank: nil,
        regime: nil,
        chain_analysis: nil,
        spot: nil,
        reason: reason,
        timestamp: Time.current
      )
    end

    def no_trade_with(reason, **attrs)
      Result.new(
        proceed: false,
        symbol: attrs[:symbol] || @symbol,
        direction: attrs[:direction],
        expiry: attrs[:expiry] || @expiry,
        selected_strike: nil,
        iv_rank: attrs[:iv_rank],
        regime: attrs[:regime],
        chain_analysis: attrs[:chain_analysis],
        spot: attrs[:spot],
        reason: reason,
        timestamp: Time.current
      )
    end
  end
end

