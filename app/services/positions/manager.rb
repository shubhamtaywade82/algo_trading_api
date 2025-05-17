# frozen_string_literal: true

module Positions
  class Manager < ApplicationService
    # ─── CHARGES CONSTANTS (rough) ──────────────────────────────────────────
    BROKERAGE                = 20.0
    GST_RATE                 = 0.18
    TRANSACTION_CHARGE_RATE  = 0.003503 / 100
    STT_RATE                 = 0.025 / 100
    SEBI_RATE                = 0.0001 / 100
    STAMP_DUTY_RATE          = 0.003 / 100
    IPFT_RATE                = 0.00005 / 100

    # ─── PERCENTAGE THRESHOLDS (can be ENV‑driven) ─────────────────────────
    EQ_TP_PCT        = ENV.fetch('EQ_TAKE_PROFIT_PCT',        20).to_f
    EQ_SL_PCT        = ENV.fetch('EQ_STOP_LOSS_PCT',          10).to_f
    EQ_TRAIL_PCT     = ENV.fetch('EQ_TRAILING_SL_PCT', 7).to_f

    OPT_TP_PCT       = ENV.fetch('OPT_TAKE_PROFIT_PCT',       40).to_f
    OPT_SL_PCT       = ENV.fetch('OPT_STOP_LOSS_PCT',         25).to_f
    OPT_TRAIL_PCT    = ENV.fetch('OPT_TRAILING_SL_PCT',       15).to_f

    TRAIL_BUFFER_PCT = 1.0 # small buffer to avoid frequent churn

    STORAGE_FILE = Rails.root.join('tmp/max_pnl_cache.yml')

    # ────────────────────────────────────────────────────────────────────────
    def call
      @peak_cache = load_cache

      fetch_positions.each do |pos|
        next unless tradable?(pos)

        # pp pos
        analysis = analyse(pos)
        # TelegramNotifier.send_message("📈 #{analysis}")
        puts analysis
        update_peak(pos, analysis)
        charges  = est_charges(analysis)
        decision = decide(pos, analysis, charges)

        puts charges
        puts decision
        place_exit_order(pos, analysis, decision[:reason]) if decision[:exit]
      end

      persist_cache
    rescue StandardError => e
      Rails.logger.error "[PositionManager] fatal: #{e.class} – #{e.message}"
    end

    # ─────────────────────────── HELPERS ────────────────────────────────────
    def fetch_positions
      Dhanhq::API::Portfolio.positions
    rescue StandardError => e
      Rails.logger.error "[PositionManager] fetch error – #{e.message}"
      []
    end

    def tradable?(p)
      p['netQty'].to_i.nonzero? && p['buyAvg'].to_f.positive?
    end

    def analyse(p)
      qty  = p['netQty'].abs
      buy  = p['buyAvg'].to_f
      ltp  = p['ltp'].to_f
      cost = buy * qty
      # pnl  = (ltp - buy) * (p['netQty'].positive? ? 1 : -1) * qty
      pnl  = p['unrealizedProfit'].to_f
      {
        symbol: p['tradingSymbol'],
        qty: qty,
        buy_price: buy,
        ltp: ltp,
        pnl: pnl,
        pnl_pct: (pnl / cost * 100).round(2),
        cost: cost,
        inst_type: p['instrument'] || infer_type(p) # EQUITY / OPTIDX / etc
      }
    end

    def infer_type(p)
      seg = p['exchangeSegment']
      return 'OPTION' if seg&.include?('FNO') && p['drvOptionType']

      seg&.include?('EQ') ? 'EQUITY' : 'OTHER'
    end

    # ─── PEAK PNL TRACKING FOR TRAILING STOP ───────────────────────────────
    def cache_key(p) = "#{p['securityId']}_#{p['exchangeSegment']}"

    def update_peak(p, analysis)
      key = cache_key(p)
      @peak_cache[key] ||= analysis[:pnl_pct]
      @peak_cache[key] = analysis[:pnl_pct] if analysis[:pnl_pct] > @peak_cache[key]
    end

    def decide(p, analysis, charges)
      cfg = cfg_for(analysis[:inst_type])
      current = analysis[:pnl_pct]
      key     = cache_key(p)
      peak    = @peak_cache[key]

      # 1. Exit if SL / TP directly hit
      reason =
        if current >= cfg[:tp]
          "TP #{current}%"
        elsif current <= -cfg[:sl]
          "SL #{current}%"
        # 2. Trailing stop only if current profit > charges
        elsif current.positive? && (analysis[:pnl] - charges).positive? && trail_hit?(current, peak, cfg[:trail])
          "TRAIL #{current}% (peak #{peak}%)"
        end

      reason ? { exit: true, reason: reason } : { exit: false }
    end

    def cfg_for(type)
      if type == 'OPTION'
        { tp: OPT_TP_PCT, sl: OPT_SL_PCT, trail: OPT_TRAIL_PCT }
      else
        { tp: EQ_TP_PCT,  sl: EQ_SL_PCT,  trail: EQ_TRAIL_PCT }
      end
    end

    def trail_hit?(current, peak, trail_pct)
      return false unless peak

      drop = peak - current
      drop >= trail_pct && current < peak - TRAIL_BUFFER_PCT
    end

    # ─── CHARGE ESTIMATE ───────────────────────────────────────────────────
    def est_charges(a)
      turnover = (a[:buy_price] + a[:ltp]) * a[:qty]
      brokerage = BROKERAGE
      txn  = turnover * TRANSACTION_CHARGE_RATE
      stt  = turnover * STT_RATE
      sebi = turnover * SEBI_RATE
      stamp = turnover * STAMP_DUTY_RATE
      ipft = turnover * IPFT_RATE
      gst  = (brokerage + txn) * GST_RATE
      (brokerage + txn + stt + sebi + stamp + ipft + gst).round(2)
    end

    # ─── EXIT EXECUTION ────────────────────────────────────────────────────
    def place_exit_order(pos, a, reason)
      payload = {
        transactionType: pos['netQty'].positive? ? 'SELL' : 'BUY',
        orderType: 'MARKET',
        productType: pos['productType'],
        validity: 'DAY',
        securityId: pos['securityId'],
        exchangeSegment: pos['exchangeSegment'],
        quantity: a[:qty]
      }

      # resp = Dhanhq::API::Orders.place(payload)
      resp = payload
      puts payload
      if resp['status'] == 'success'
        Rails.logger.info "[PositionManager] ✔ exited #{a[:symbol]} – #{reason}"
      else
        Rails.logger.error "[PositionManager] ✖ exit failed #{a[:symbol]} – #{resp}"
      end

      ExitLog.create!(
        trading_symbol: a[:symbol],
        security_id: pos['securityId'],
        reason: reason,
        order_id: resp['orderId'],
        exit_price: a[:ltp],
        exit_time: Time.zone.now
      )
    rescue StandardError => e
      Rails.logger.error "[PositionManager] order error #{a[:symbol]} – #{e.message}"
    end

    # ─── PEAK‑CACHE PERSISTENCE ────────────────────────────────────────────
    def load_cache
      if File.exist?(STORAGE_FILE)
        YAML.safe_load_file(STORAGE_FILE) || {}
      else
        {}
      end
    end

    def persist_cache
      File.write(STORAGE_FILE, @peak_cache.to_yaml)
    end
  end
end
