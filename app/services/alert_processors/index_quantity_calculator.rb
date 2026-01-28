# frozen_string_literal: true

module AlertProcessors
  # Capital-aware quantity calculation for index options.
  # Uses allocation %, risk per trade %, and optional 1-lot grace when alloc-bound is tight.
  class IndexQuantityCalculator
    CAPITAL_BANDS = [
      { upto: 75_000, alloc_pct: 0.30, risk_per_trade_pct: 0.050, daily_max_loss_pct: 0.050 },
      { upto: 150_000, alloc_pct: 0.25, risk_per_trade_pct: 0.035, daily_max_loss_pct: 0.060 },
      { upto: 300_000, alloc_pct: 0.20, risk_per_trade_pct: 0.030, daily_max_loss_pct: 0.060 },
      { upto: Float::INFINITY, alloc_pct: 0.20, risk_per_trade_pct: 0.025, daily_max_loss_pct: 0.050 }
    ].freeze

    DEFAULT_STOP_LOSS_PCT = 0.18

    def self.policy(balance)
      band = CAPITAL_BANDS.find { |b| balance <= b[:upto] } || CAPITAL_BANDS.last
      {
        alloc_pct: ENV['ALLOC_PCT']&.to_f || band[:alloc_pct],
        risk_per_trade_pct: ENV['RISK_PER_TRADE_PCT']&.to_f || band[:risk_per_trade_pct],
        daily_max_loss_pct: ENV['DAILY_MAX_LOSS_PCT']&.to_f || band[:daily_max_loss_pct]
      }
    end

    def self.quantity(strike:, lot_size:, balance:, sl_pct: DEFAULT_STOP_LOSS_PCT, return_details: false)
      lot_size = lot_size.to_i
      price = strike[:last_price].to_f
      if lot_size.zero? || price <= 0
        return return_details ? { quantity: 0, invalid: true, lot_size: lot_size, price: price } : 0
      end

      policy = self.policy(balance)
      alloc_cap = balance * policy[:alloc_pct]
      per_lot_cost = price * lot_size
      if per_lot_cost > balance
        return return_details ? { quantity: 0, alloc_cap: alloc_cap, per_lot_cost: per_lot_cost, balance: balance } : 0
      end

      max_lots_by_alloc = (alloc_cap / per_lot_cost).floor
      per_lot_risk = per_lot_cost * sl_pct
      risk_cap = balance * policy[:risk_per_trade_pct]
      max_lots_by_risk = per_lot_risk.positive? ? (risk_cap / per_lot_risk).floor : 0
      max_lots_by_afford = (balance / per_lot_cost).floor

      lots = [max_lots_by_alloc, max_lots_by_risk, max_lots_by_afford].min

      if lots.zero? && per_lot_cost <= balance && per_lot_risk <= risk_cap
        lots = 1
      end

      if lots.zero?
        details = { quantity: 0, alloc_cap: alloc_cap, risk_cap: risk_cap, per_lot_cost: per_lot_cost, per_lot_risk: per_lot_risk }
        return return_details ? details : 0
      end

      qty = lots * lot_size
      if return_details
        { quantity: qty, lots: lots, alloc_cap: alloc_cap, risk_cap: risk_cap, per_lot_cost: per_lot_cost, per_lot_risk: per_lot_risk, sl_pct: sl_pct }
      else
        qty
      end
    end
  end
end
