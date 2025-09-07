require 'rails_helper'

RSpec.describe SwingPick, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:instrument) }
  end

  describe 'enums' do
    describe 'status' do
      it 'has correct status values' do
        expect(SwingPick.statuses.keys).to match_array(%w[pending triggered closed])
      end

      it 'can be set to pending' do
        swing_pick = build(:swing_pick, status: 'pending')
        expect(swing_pick.pending?).to be true
      end

      it 'can be set to triggered' do
        swing_pick = build(:swing_pick, status: 'triggered')
        expect(swing_pick.triggered?).to be true
      end

      it 'can be set to closed' do
        swing_pick = build(:swing_pick, status: 'closed')
        expect(swing_pick.closed?).to be true
      end
    end
  end

  describe 'scopes and queries' do
    let!(:instrument1) { create(:instrument, symbol_name: 'TCS', security_id: '11536') }
    let!(:instrument2) { create(:instrument, symbol_name: 'INFY', security_id: '408065') }
    let!(:instrument3) { create(:instrument, symbol_name: 'HDFC', security_id: '1333') }
    let!(:pending_pick) { create(:swing_pick, status: 'pending', instrument: instrument1) }
    let!(:triggered_pick) { create(:swing_pick, status: 'triggered', instrument: instrument2) }
    let!(:closed_pick) { create(:swing_pick, status: 'closed', instrument: instrument3) }

    it 'can find pending picks' do
      expect(SwingPick.pending).to include(pending_pick)
      expect(SwingPick.pending).not_to include(triggered_pick, closed_pick)
    end

    it 'can find triggered picks' do
      expect(SwingPick.triggered).to include(triggered_pick)
      expect(SwingPick.triggered).not_to include(pending_pick, closed_pick)
    end

    it 'can find closed picks' do
      expect(SwingPick.closed).to include(closed_pick)
      expect(SwingPick.closed).not_to include(pending_pick, triggered_pick)
    end
  end

  describe 'factory' do
    it 'creates a valid swing pick' do
      swing_pick = build(:swing_pick)
      expect(swing_pick).to be_valid
    end

    it 'creates a swing pick with pending status by default' do
      swing_pick = create(:swing_pick)
      expect(swing_pick.status).to eq('pending')
    end
  end
end
