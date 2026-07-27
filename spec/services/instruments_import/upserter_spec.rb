# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstrumentsImport::Upserter, type: :service do
  def derivative_row(**overrides)
    {
      exchange: 'NSE', segment: 'D', security_id: '45001', symbol_name: 'NIFTY-Jul2026-25000-CE',
      isin: 'NA', instrument_code: 'OPTIDX', instrument_type: 'OPTIDX', underlying_symbol: 'NIFTY',
      underlying_security_id: '13', series: 'NA', lot_size: 75, tick_size: 0.05,
      expiry_date: Date.new(2026, 7, 30), strike_price: 25_000.0, option_type: 'CE',
      expiry_flag: 'M', active: true, last_seen_at: Time.current,
      created_at: Time.current, updated_at: Time.current
    }.merge(overrides)
  end

  def instrument_row(**overrides)
    {
      exchange: 'NSE', segment: 'I', security_id: '13', symbol_name: 'NIFTY', display_name: 'Nifty 50',
      isin: 'NA', instrument_code: 'INDEX', instrument_type: 'INDEX', underlying_symbol: 'NIFTY',
      underlying_security_id: '13', series: 'NA', lot_size: 1, tick_size: 0.05,
      expiry_date: nil, strike_price: nil, option_type: nil, expiry_flag: 'N',
      active: true, last_seen_at: Time.current, created_at: Time.current, updated_at: Time.current
    }.merge(overrides)
  end

  describe 'derivatives whose underlying was not resolved' do
    # Regression: Mapper writes :instrument_id only onto the contracts whose
    # underlying it found, and the Upserter imports both halves as one batch so
    # an unparented contract is stored rather than dropped. activerecord-import
    # requires a uniform key set across the batch, so the mixed batch every real
    # scrip master produces aborted the whole import with
    # "Hash key mismatch. ... Missing keys: [:instrument_id]".
    it 'imports a batch that mixes parented and unparented contracts' do
      parent = create(:instrument, :nifty)
      rows = [
        derivative_row(instrument_id: parent.id),
        derivative_row(security_id: '45002', symbol_name: 'SX50OPT', underlying_symbol: 'SENSEX50')
      ]

      expect { described_class.call(instruments_rows: [], derivatives_rows: rows) }
        .to change(Derivative, :count).by(2)
    end

    it 'stores the unparented contract with a null instrument_id' do
      rows = [derivative_row(security_id: '45002', symbol_name: 'SX50OPT')]

      described_class.call(instruments_rows: [], derivatives_rows: rows)

      expect(Derivative.find_by(security_id: '45002').instrument_id).to be_nil
    end

    it 'clears an instrument_id that no longer resolves rather than failing the FK' do
      stale_id = create(:instrument, :nifty).id + 1_000

      described_class.call(instruments_rows: [], derivatives_rows: [derivative_row(instrument_id: stale_id)])

      expect(Derivative.find_by(security_id: '45001').instrument_id).to be_nil
    end
  end

  describe 'idempotency' do
    it 'upserts on the natural key instead of inserting a second row' do
      described_class.call(instruments_rows: [instrument_row], derivatives_rows: [])

      expect { described_class.call(instruments_rows: [instrument_row(display_name: 'NIFTY 50')], derivatives_rows: []) }
        .not_to change(Instrument, :count)
    end

    it 'refreshes the columns the feed still carries' do
      described_class.call(instruments_rows: [instrument_row], derivatives_rows: [])

      described_class.call(instruments_rows: [instrument_row(display_name: 'NIFTY 50')], derivatives_rows: [])

      expect(Instrument.find_by(security_id: '13').display_name).to eq('NIFTY 50')
    end
  end
end
