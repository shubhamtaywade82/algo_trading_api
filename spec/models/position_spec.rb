require 'rails_helper'

RSpec.describe Position do
  describe 'associations' do
    it { is_expected.to belong_to(:instrument) }
  end

  describe 'enums' do
    describe 'position_type' do
      it 'has correct position types' do
        expect(described_class.position_types.keys).to match_array(%w[long short closed])
      end

      it 'can be set to long' do
        position = build(:position, position_type: 'long')
        expect(position.long?).to be true
      end

      it 'can be set to short' do
        position = build(:position, position_type: 'short')
        expect(position.short?).to be true
      end

      it 'can be set to closed' do
        position = build(:position, position_type: 'closed')
        expect(position.closed?).to be true
      end
    end

    describe 'product_type' do
      it 'has correct product types' do
        expect(described_class.product_types.keys).to match_array(%w[cnc intraday margin mtf co bo])
      end

      it 'can be set to intraday' do
        position = build(:position, product_type: 'intraday')
        expect(position.intraday?).to be true
      end

      it 'can be set to cnc' do
        position = build(:position, product_type: 'cnc')
        expect(position.cnc?).to be true
      end

      it 'can be set to margin' do
        position = build(:position, product_type: 'margin')
        expect(position.margin?).to be true
      end
    end

    describe 'exchange_segment' do
      it 'has correct exchange segments' do
        expect(described_class.exchange_segments.keys).to match_array(%w[nse_eq nse_fno bse_eq bse_fno mcx_comm])
      end

      it 'can be set to nse_eq' do
        position = build(:position, exchange_segment: 'nse_eq')
        expect(position.nse_eq?).to be true
      end

      it 'can be set to nse_fno' do
        position = build(:position, exchange_segment: 'nse_fno')
        expect(position.nse_fno?).to be true
      end

      it 'can be set to bse_eq' do
        position = build(:position, exchange_segment: 'bse_eq')
        expect(position.bse_eq?).to be true
      end

      it 'can be set to mcx_comm' do
        position = build(:position, exchange_segment: 'mcx_comm')
        expect(position.mcx_comm?).to be true
      end
    end
  end

  describe 'scopes and queries' do
    let!(:instrument1) { create(:instrument, symbol_name: 'TCS', security_id: '11536') }
    let!(:instrument2) { create(:instrument, symbol_name: 'INFY', security_id: '408065') }
    let!(:instrument3) { create(:instrument, symbol_name: 'HDFC', security_id: '1333') }
    let!(:long_position) { create(:position, position_type: 'long', security_id: '11536', instrument: instrument1) }
    let!(:short_position) { create(:position, position_type: 'short', security_id: '408065', instrument: instrument2) }
    let!(:closed_position) { create(:position, position_type: 'closed', security_id: '1333', instrument: instrument3) }

    it 'can find long positions' do
      expect(described_class.long).to include(long_position)
      expect(described_class.long).not_to include(short_position, closed_position)
    end

    it 'can find short positions' do
      expect(described_class.short).to include(short_position)
      expect(described_class.short).not_to include(long_position, closed_position)
    end

    it 'can find closed positions' do
      expect(described_class.closed).to include(closed_position)
      expect(described_class.closed).not_to include(long_position, short_position)
    end
  end

  describe 'factory' do
    it 'creates a valid position' do
      instrument = create(:instrument, symbol_name: 'TCS', security_id: '11536')
      position = build(:position, instrument: instrument)
      expect(position).to be_valid
    end

    it 'creates a position with required instrument association' do
      instrument = create(:instrument, symbol_name: 'TCS', security_id: '11536')
      position = create(:position, instrument: instrument)
      expect(position.instrument).to be_present
    end
  end
end
