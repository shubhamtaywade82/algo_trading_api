# frozen_string_literal: true

# Indexes for the three lookups this app actually performs at runtime.
#
# Before this, `derivatives` had exactly one useful index for reads —
# (underlying_symbol, expiry_date) — and every strike/option_type filter on top
# of it was a heap scan over the whole expiry. Tick mapping
# (Dhan::WS::FeedListener, Orders::Manager, Paper::Positions) looked rows up by
# security_id alone, which could only use the leading column of the
# (security_id, symbol_name, exchange, segment) unique index and matched across
# every segment.
class AddInstrumentLookupIndexes < ActiveRecord::Migration[8.0]
  def change
    # 1. Tick/order → row. The WebSocket addresses instruments as
    #    (exchange_segment, security_id) and so does every DhanHQ order payload.
    #    Deliberately not unique: DhanHQ folds NSE and BSE indices into a single
    #    IDX_I segment, so uniqueness here is not ours to assert.
    add_index :instruments, %i[exchange_segment security_id],
              name: 'index_instruments_on_segment_and_security_id'
    add_index :derivatives, %i[exchange_segment security_id],
              name: 'index_derivatives_on_segment_and_security_id'

    # 2. Option chain. Trading::DerivativeResolver, AlertProcessors::Index and
    #    Option::* all filter on exactly this tuple. Partial on `active` so
    #    retired contracts do not bloat the index that sizes every entry.
    #
    #    Column order matches Derivative.options_chain's ORDER BY
    #    (strike_price, option_type), so the index can return the chain already
    #    sorted. Putting option_type before strike_price — the obvious reading
    #    of "filter by CE/PE, then strike" — cannot, because a chain wants both
    #    sides interleaved by strike rather than one side after the other.
    #
    #    Measured on 120k contracts: resolving a single strike before an order
    #    (underlying + expiry + strike + option_type, the DerivativeResolver
    #    path) is an index-only condition on all four columns at ~0.07ms, and a
    #    strike window around spot scans the index for the range. For a whole
    #    expiry the planner may still prefer a bitmap scan plus a sort; that is
    #    a costing decision, not a missing capability.
    add_index :derivatives,
              %i[underlying_symbol expiry_date strike_price option_type],
              name: 'index_derivatives_on_options_chain',
              where: 'active AND underlying_symbol IS NOT NULL'

    # 3. Expiry discovery for a known underlying (expiry_list, rollover checks).
    add_index :derivatives, %i[instrument_id expiry_date],
              name: 'index_derivatives_on_instrument_and_expiry',
              where: 'instrument_id IS NOT NULL'

    # 4. Universe scans: Screeners::StocksScreener and Catalog::FactorScoreEngine
    #    both walk (exchange, segment, instrument_code).
    add_index :instruments, %i[segment instrument_code active],
              name: 'index_instruments_on_segment_and_code'

    # 5. Staleness sweeps by the importer.
    add_index :instruments, :last_seen_at
    add_index :derivatives, :last_seen_at
  end
end
