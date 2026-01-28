# spec/services/positions/active_cache_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Positions::ActiveCache, type: :service do
  # ------------------------------------------------------------------
  # Test data helpers
  # ------------------------------------------------------------------
  let(:pos_eq_enum) { { 'securityId' => 'EQ123',  'exchangeSegment' => 1, 'netQty' => 10 } }
  let(:pos_fno_str) { { 'securityId' => 'OPT456', 'exchangeSegment' => 'NSE_FNO', 'netQty' => -5 } }
  let(:flat_pos)    { { 'securityId' => 'FLAT',   'exchangeSegment' => 1, 'netQty' => 0 } }

  # ------------------------------------------------------------------
  # Per-example setup – stubs *and* cache clear
  # ------------------------------------------------------------------
  before do
    Rails.cache.clear

    # Stub the mappings every example so each spec sees a fresh constant
    stub_const('DhanhqMappings', Module.new) unless defined?(DhanhqMappings)
    stub_const('DhanhqMappings::SEGMENT_ENUM_TO_KEY', { 1 => 'NSE_EQ', 2 => 'NSE_FNO' })
    stub_const('DhanhqMappings::SEGMENT_KEY_TO_ENUM', { 'NSE_EQ' => 1, 'NSE_FNO' => 2 })

    # Stub DhanHQ positions API (ActiveCache calls Position.all.map(&:attributes)
    position_objects = [
      double('Position', attributes: pos_eq_enum),
      double('Position', attributes: pos_fno_str),
      double('Position', attributes: flat_pos)
    ]
    allow(DhanHQ::Models::Position).to receive(:all).and_return(position_objects)
  end

  # ------------------------------------------------------------------
  describe '.refresh!' do
    before { described_class.refresh! }

    it 'stores only non-zero positions keyed by securityId + segment' do
      # pos_eq_enum has exchangeSegment 1 → reverse_convert_segment => 'NSE_EQ'; pos_fno_str has 'NSE_FNO' → => 2
      expect(described_class.keys).to match_array(%w[EQ123_NSE_EQ OPT456_2])
    end

    it 'exposes helpers #all, #ids, #all_positions' do
      expect(described_class.ids).to contain_exactly('EQ123', 'OPT456')
      expect(described_class.all_positions)
        .to contain_exactly(pos_eq_enum, pos_fno_str)
    end
  end

  # ------------------------------------------------------------------
  describe '.fetch' do
    before { described_class.refresh! }

    it 'fetches by (security_id, segment enum)' do
      # row was stored with enum 1 → fetch with enum
      expect(described_class.fetch('EQ123', 1)).to eq(pos_eq_enum)
    end

    it 'fetches by (security_id, segment key)' do
      # row was stored with key 'NSE_FNO' → fetch with key
      expect(described_class.fetch('OPT456', 'NSE_FNO')).to eq(pos_fno_str)
    end

    it 'returns nil when key is missing' do
      expect(described_class.fetch('XXX', 'NSE_FNO')).to be_nil
    end
  end

  # ------------------------------------------------------------------
  describe '.key_for and .reverse_convert_segment' do
    it 'generates deterministic composite keys' do
      expect(described_class.key_for('ID1', 'NSE_FNO')).to eq('ID1_NSE_FNO')
      expect(described_class.key_for('ID2', 1)).to eq('ID2_1')
    end

    it 'maps enums ↔︎ keys correctly' do
      expect(described_class.reverse_convert_segment(1)).to eq('NSE_EQ')
      expect(described_class.reverse_convert_segment('NSE_FNO')).to eq(2)
    end
  end
end
