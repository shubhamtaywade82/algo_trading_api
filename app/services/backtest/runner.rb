# frozen_string_literal: true

module Backtest
  class Runner
    def self.call(symbol:, from_date:, to_date:, strategy: :expiry_range_strategy, use_llm: false, **options)
      new(symbol: symbol, from_date: from_date, to_date: to_date, strategy: strategy, use_llm: use_llm, **options).run
    end

    def initialize(symbol:, from_date:, to_date:, strategy:, use_llm: false, **options)
      @symbol = symbol.to_s.upcase
      @from_date = Date.parse(from_date.to_s)
      @to_date = Date.parse(to_date.to_s)
      @strategy = strategy.to_sym
      @use_llm = use_llm
      @options = options
      @trades = []
      @decisions = [] # Track all decisions for statistics
      @current_position = nil
    end

    def run
      instrument = find_instrument
      return error_result("Instrument not found: #{@symbol}") unless instrument

      trading_days = MarketCalendar.trading_days_between(@from_date, @to_date)
      return error_result('No trading days in range') if trading_days.empty?

      Rails.logger.info "[Backtest] Running #{@strategy} for #{@symbol} from #{@from_date} to #{@to_date} (#{trading_days.size} trading days)"

      trading_days.each_with_index do |date, index|
        Rails.logger.info "[Backtest] Processing day #{index + 1}/#{trading_days.size}: #{date}"
        replay_day(instrument, date)
      end

      build_result
    end

    private

    def find_instrument
      Instrument.where(exchange: :nse, segment: :index)
                .find_by(underlying_symbol: @symbol)
    end

    def replay_day(instrument, date)
      # Set time to a specific point in the trading day (e.g., 10:00 AM)
      analysis_time = date.to_time.change(hour: 10, min: 0)

      # Fetch historical candles up to this date
      candle_series = fetch_historical_candles(instrument, date)
      return if candle_series.candles.empty?

      # Build market snapshot for this date
      md = build_market_snapshot(instrument, candle_series, date, analysis_time)

      # Run strategy
      decision = run_strategy(md, candle_series, date)

      # Process decision (entry/exit)
      process_decision(decision, instrument, date, md)
    rescue StandardError => e
      Rails.logger.error "[Backtest] Error replaying #{date}: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    def fetch_historical_candles(instrument, date)
      # Fetch candles up to the target date
      to_date = date
      from_date = date - 30.days # Get enough history for indicators

      sleep(1.2) # Rate limit: ~1 call per second
      raw = instrument.intraday_ohlc(
        interval: '5',
        from_date: from_date.to_s,
        to_date: to_date.to_s
      )

      series = CandleSeries.new(symbol: instrument.symbol_name, interval: '5')
      series.load_from_raw(raw)
      series
    end

    def build_market_snapshot(instrument, candle_series, date, analysis_time)
      # Get previous day's OHLC
      prev_day = MarketCalendar.last_trading_day(from: date - 1)
      prev_day_ohlc = fetch_previous_day_ohlc(instrument, prev_day)

      # Build snapshot similar to AnalysisService
      {
        symbol: instrument.symbol_name,
        ts: analysis_time,
        frame: '15m',
        expiry: find_expiry_for_date(instrument, date),
        ltp: candle_series.closes.last,
        session: :live,
        ohlc: {
          open: PriceMath.round_tick(candle_series.opens.last),
          high: PriceMath.round_tick(candle_series.highs.last),
          low: PriceMath.round_tick(candle_series.lows.last),
          close: PriceMath.round_tick(candle_series.closes.last),
          volume: candle_series.candles.last&.volume || 0
        },
        prev_day: prev_day_ohlc,
        boll: candle_series.bollinger_bands(period: 20),
        atr: candle_series.atr[:atr].round(2),
        rsi: candle_series.rsi[:rsi].round(2),
        macd: candle_series.macd.transform_values { |v| v.round(2) },
        ema14: candle_series.moving_average(14)[:ema].round(2),
        super: candle_series.supertrend_signal,
        hi20: candle_series.recent_highs(20)[:highs].max.round(2),
        lo20: candle_series.recent_lows(20)[:lows].min.round(2),
        liq_up: candle_series.liquidity_grab_up?(lookback: 20)[:liquidity_grab_up],
        liq_dn: candle_series.liquidity_grab_down?(lookback: 20)[:liquidity_grab_down],
        options: fetch_option_chain_snapshot(instrument, date),
        vix: fetch_vix_for_date(date),
        regime: {}
      }
    end

    def fetch_previous_day_ohlc(instrument, date)
      # API requires from_date < to_date, so use day before as from_date
      from_date = MarketCalendar.last_trading_day(from: date - 1)
      to_date = date

      sleep(1.2) # Rate limit: ~1 call per second
      bars = instrument.historical_ohlc(
        from_date: from_date.to_s,
        to_date: to_date.to_s
      )
      return nil if bars.blank?

      {
        open: PriceMath.round_tick(bars['open'].last.to_f),
        high: PriceMath.round_tick(bars['high'].last.to_f),
        low: PriceMath.round_tick(bars['low'].last.to_f),
        close: PriceMath.round_tick(bars['close'].last.to_f)
      }
    end

    def find_expiry_for_date(instrument, date)
      # Find the nearest expiry on or after this date
      expiries = instrument.expiry_list || []
      expiries.find { |e| Date.parse(e) >= date } || expiries.last
    end

    def fetch_option_chain_snapshot(_instrument, _date)
      # For backtesting, we'd need historical option chain data
      # This is a simplified version - in production you'd need historical option prices
      nil # Return nil for now, or implement historical option chain fetching
    end

    def fetch_vix_for_date(date)
      # Fetch historical VIX for the date
      # API requires from_date < to_date
      vix_instrument = Instrument.find_by(security_id: 21)
      return nil unless vix_instrument

      prev_day = MarketCalendar.last_trading_day(from: date - 1)
      from_date = prev_day
      to_date = date

      sleep(1.2) # Rate limit: ~1 call per second
      bars = vix_instrument.historical_ohlc(
        from_date: from_date.to_s,
        to_date: to_date.to_s
      )
      return nil if bars.blank?

      bars['close'].last.to_f
    end

    def run_strategy(md, candle_series, date)
      case @strategy
      when :expiry_range_strategy
        run_expiry_range_strategy(md, candle_series, date)
      when :options_buying
        run_options_buying_strategy(md, candle_series, date)
      else
        { decision: 'NO_TRADE', reason: 'Unknown strategy' }
      end
    end

    def run_expiry_range_strategy(md, candle_series, date)
      series_5m = candle_series
      vix_series_5m = fetch_vix_series(date)
      vix_instrument = Instrument.find_by(security_id: 21)

      # Create a VIX snapshot using historical date context
      vix_snapshot = build_vix_snapshot_for_date(vix_instrument, vix_series_5m, date)

      Strategies::ExpiryRangeStrategy.call(md: md, series_5m: series_5m, vix_snapshot: vix_snapshot)
    end

    def build_vix_snapshot_for_date(vix_instrument, vix_series_5m, date)
      return Vix::Guard::Snapshot.new(price: 0, slope: 0, pdh: 0, pwl: 0) unless vix_instrument

      # Use historical date context instead of current date
      prev_day = MarketCalendar.last_trading_day(from: date - 1)
      week_start = MarketCalendar.last_trading_day(from: date - 7)

      # For prev_day range, use day before as from_date
      from_date_prev = MarketCalendar.last_trading_day(from: prev_day - 1)
      to_date_prev = prev_day
      to_date_week = prev_day

      sleep(1.2) # Rate limit
      bars_prev = vix_instrument.historical_ohlc(from_date: from_date_prev.to_s, to_date: to_date_prev.to_s) || {}

      sleep(1.2) # Rate limit
      bars_week = vix_instrument.historical_ohlc(from_date: week_start.to_s, to_date: to_date_week.to_s) || {}

      pdh = Array(bars_prev['high']).map(&:to_f).max || 0
      pwl = Array(bars_week['low']).map(&:to_f).min || 0

      # Get VIX price for the date (use close from bars_prev or fetch separately)
      vix_price = bars_prev['close']&.last&.to_f || fetch_vix_for_date(date) || 0

      Vix::Guard::Snapshot.new(
        price: vix_price,
        slope: Indicators::Slope.call(series: vix_series_5m, lookback: 24),
        pdh: pdh,
        pwl: pwl
      )
    end

    def run_options_buying_strategy(md, candle_series, date)
      # Enrich with SMC/AVRZ
      enrich_with_structure_and_value!(md, candle_series, date)

      # Check if ready
      unless ready_for_options_buying?(md)
        missing = missing_requirements(md)
        decision = {
          decision: 'NO_TRADE',
          reason: "Missing SMC/AVRZ inputs: #{missing.join(', ')}",
          market_bias: 'UNCLEAR'
        }
        @decisions << { date: date, decision: decision }
        return decision
      end

      return run_llm_decision(md, date) if @use_llm

      # Actually call LLM (expensive but accurate)

      # Use deterministic rule-based approach for faster backtesting
      run_rule_based_decision(md, date)
    end

    def run_llm_decision(md, date)
      prompt = Market::PromptBuilder.build_prompt(md, trade_type: :options_buying)

      answer = Openai::ChatRouter.ask!(
        prompt,
        system: Market::PromptBuilder.system_prompt(@strategy)
      )

      validated = Market::AiTradeValidator.call!(
        answer,
        instrument_symbol: md[:symbol],
        options_snapshot: md[:options]
      )

      decision_hash = {
        decision: validated.decision,
        instrument: validated.instrument,
        bias: validated.bias,
        reason: validated.reason,
        option: validated.option,
        execution: validated.execution,
        underlying_context: validated.underlying_context,
        exit_rules: validated.exit_rules,
        no_trade_because: validated.no_trade_because,
        trigger_conditions: validated.trigger_conditions,
        preferred_option: validated.preferred_option,
        market_bias: validated.market_bias,
        risk_note: validated.risk_note,
        re_evaluate_when: validated.re_evaluate_when
      }

      @decisions << { date: date, decision: decision_hash }
      decision_hash
    rescue Market::AiTradeValidator::ValidationError => e
      Rails.logger.warn "[Backtest] AI validation failed for #{date}: #{e.message}"
      decision = {
        decision: 'NO_TRADE',
        reason: "AI validation failed: #{e.message}",
        market_bias: 'UNCLEAR'
      }
      @decisions << { date: date, decision: decision }
      decision
    end

    def run_rule_based_decision(md, date)
      # Simple rule-based decision for faster backtesting
      # This is a placeholder - you can implement your own rules
      smc_15m = md.dig(:smc, :m15)
      avrz_15m = md.dig(:value, :m15, :avrz)
      ltp = md[:ltp]

      return { decision: 'NO_TRADE', reason: 'No SMC/AVRZ data', market_bias: 'UNCLEAR' } unless smc_15m && avrz_15m

      # Simple rule: Buy if price is at AVRZ extremes and structure confirms
      at_avrz_low = ltp <= avrz_15m[:low]
      at_avrz_high = ltp >= avrz_15m[:high]
      structure_bullish = smc_15m.market_structure == :bullish
      structure_bearish = smc_15m.market_structure == :bearish

      decision = if at_avrz_low && structure_bullish
                   {
                     decision: 'BUY',
                     instrument: md[:symbol],
                     bias: 'BULLISH',
                     reason: 'Price at AVRZ low with bullish structure',
                     option: { type: 'CE', strike: (ltp / 50).round * 50 }, # Simplified strike selection
                     execution: {
                       entry_premium: 100.0, # Placeholder - would need historical option prices
                       stop_loss_premium: 80.0,
                       target_premium: 150.0,
                       risk_reward: 1.5
                     }
                   }
                 elsif at_avrz_high && structure_bearish
                   {
                     decision: 'BUY',
                     instrument: md[:symbol],
                     bias: 'BEARISH',
                     reason: 'Price at AVRZ high with bearish structure',
                     option: { type: 'PE', strike: (ltp / 50).round * 50 },
                     execution: {
                       entry_premium: 100.0,
                       stop_loss_premium: 80.0,
                       target_premium: 150.0,
                       risk_reward: 1.5
                     }
                   }
                 else
                   {
                     decision: 'WAIT',
                     instrument: md[:symbol],
                     bias: smc_15m.market_structure.to_s.upcase,
                     reason: 'Price not at AVRZ extremes or structure unclear',
                     no_trade_because: ['Price not at AVRZ extremes'],
                     trigger_conditions: ['Price reaches AVRZ low/high with structure confirmation']
                   }
                 end

      @decisions << { date: date, decision: decision }
      decision
    end

    def missing_requirements(md)
      missing = []
      smc_15m = md.dig(:smc, :m15)
      avrz_15m = md.dig(:value, :m15, :avrz)
      vwap_15m = md.dig(:value, :m15, :vwap)

      missing << 'SMC_15m' unless smc_15m.present?
      missing << 'swing_high' if smc_15m.present? && smc_15m.last_swing_high.blank?
      missing << 'swing_low' if smc_15m.present? && smc_15m.last_swing_low.blank?
      missing << 'VWAP_15m' unless vwap_15m.present?
      missing << 'AVRZ_15m' unless avrz_15m.present?
      missing << 'AVRZ_low' if avrz_15m.present? && avrz_15m[:low].blank?
      missing << 'AVRZ_high' if avrz_15m.present? && avrz_15m[:high].blank?

      missing
    end

    def enrich_with_structure_and_value!(md, candle_series, date)
      session_date = date
      series_5m = candle_series
      series_15m = candle_series # Simplified - in real backtest, fetch 15m candles

      md[:smc] = {
        m5: Market::Structure::SmcAnalyzer.call(series_5m, timeframe_minutes: 5),
        m15: Market::Structure::SmcAnalyzer.call(series_15m, timeframe_minutes: 15)
      }

      md[:value] = {
        m5: value_snapshot(series_5m, smc: md.dig(:smc, :m5), session_date: session_date, vix: md[:vix]),
        m15: value_snapshot(series_15m, smc: md.dig(:smc, :m15), session_date: session_date, vix: md[:vix])
      }
    end

    def value_snapshot(series, smc:, session_date:, vix:)
      return {} if series.candles.empty?

      candle_date = series.candles.last&.timestamp&.to_date || session_date
      vwap = Market::Value::VwapCalculator.session_vwap(series, session_date: candle_date)

      bos_ts = smc&.last_bos&.dig(:ts)
      avwap_bos = bos_ts ? Market::Value::VwapCalculator.anchored_vwap(series, from_ts: bos_ts, session_date: candle_date) : nil

      atr_points = series.atr[:atr].to_f
      avrz = Market::Value::AvrzCalculator.call(mid: vwap, atr_points: atr_points, vix: vix)

      {
        vwap: vwap,
        avwap_bos: avwap_bos,
        avrz: avrz
      }
    end

    def ready_for_options_buying?(md)
      smc_15m = md.dig(:smc, :m15)
      avrz_15m = md.dig(:value, :m15, :avrz)
      vwap_15m = md.dig(:value, :m15, :vwap)

      smc_15m.present? &&
        smc_15m.last_swing_high.present? &&
        smc_15m.last_swing_low.present? &&
        vwap_15m.present? &&
        avrz_15m.present? &&
        avrz_15m[:low].present? &&
        avrz_15m[:high].present?
    end

    def fetch_vix_series(date)
      vix_instrument = Instrument.find_by(security_id: 21)
      return CandleSeries.new(symbol: 'VIX', interval: '5') unless vix_instrument

      sleep(1.2) # Rate limit: ~1 call per second
      raw = vix_instrument.intraday_ohlc(
        interval: '5',
        from_date: (date - 7).to_s,
        to_date: date.to_s
      )

      series = CandleSeries.new(symbol: 'VIX', interval: '5')
      series.load_from_raw(raw)
      series
    end

    def process_decision(decision, instrument, date, md)
      case decision
      when Hash
        case decision[:decision] || decision['decision']
        when 'BUY'
          enter_trade(decision, instrument, date, md)
        when 'NO_TRADE', 'WAIT'
          # Do nothing
        end
      end
    end

    def enter_trade(decision, instrument, date, md)
      # Extract trade details from decision
      option_type = decision[:option]&.dig(:type) || decision['option']&.dig('type')
      strike = decision[:option]&.dig(:strike) || decision['option']&.dig('strike')
      entry_premium = decision[:execution]&.dig(:entry_premium) || decision['execution']&.dig('entry_premium')
      stop_loss = decision[:execution]&.dig(:stop_loss_premium) || decision['execution']&.dig('stop_loss_premium')
      target = decision[:execution]&.dig(:target_premium) || decision['execution']&.dig('target_premium')

      return unless option_type && strike && entry_premium

      @trades << {
        entry_date: date,
        symbol: instrument.symbol_name,
        option_type: option_type,
        strike: strike,
        entry_premium: entry_premium.to_f,
        stop_loss: stop_loss.to_f,
        target: target.to_f,
        entry_spot: md[:ltp],
        decision: decision
      }

      Rails.logger.debug { "[Backtest] Entry: #{option_type} #{strike} @ #{entry_premium} on #{date}" }
    end

    def build_result
      {
        symbol: @symbol,
        strategy: @strategy,
        from_date: @from_date,
        to_date: @to_date,
        total_trades: @trades.size,
        trades: @trades,
        total_decisions: @decisions.size,
        decisions_summary: summarize_decisions,
        metrics: calculate_metrics
      }
    end

    def summarize_decisions
      return {} if @decisions.empty?

      by_decision = @decisions.group_by { |d| d[:decision][:decision] || d[:decision]['decision'] }
      {
        buy: by_decision['BUY']&.size || 0,
        wait: by_decision['WAIT']&.size || 0,
        no_trade: by_decision['NO_TRADE']&.size || 0
      }
    end

    def calculate_metrics
      if @decisions.empty?
        return {
          total_trades: 0,
          total_decisions: @decisions.size,
          buy_rate: 0,
          wait_rate: 0,
          no_trade_rate: 0
        }
      end

      summary = summarize_decisions
      total = @decisions.size

      {
        total_trades: @trades.size,
        total_decisions: total,
        buy_rate: (summary[:buy].to_f / total * 100).round(2),
        wait_rate: (summary[:wait].to_f / total * 100).round(2),
        no_trade_rate: (summary[:no_trade].to_f / total * 100).round(2)
      }
    end

    def error_result(message)
      {
        error: message,
        symbol: @symbol,
        strategy: @strategy
      }
    end
  end
end
