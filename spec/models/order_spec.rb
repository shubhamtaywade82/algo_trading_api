require 'rails_helper'

RSpec.describe Order do
  describe 'associations' do
    it { is_expected.to belong_to(:alert).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:dhan_order_id) }
  end

  describe 'enums' do
    describe 'transaction_type' do
      it 'has correct transaction types' do
        expect(described_class.transaction_types.keys).to match_array(%w[buy sell])
      end

      it 'can be set to buy' do
        order = build(:order, transaction_type: 'buy')
        expect(order.transaction_type_buy?).to be true
      end

      it 'can be set to sell' do
        order = build(:order, transaction_type: 'sell')
        expect(order.transaction_type_sell?).to be true
      end
    end

    describe 'product_type' do
      it 'has correct product types' do
        expect(described_class.product_types.keys).to match_array(%w[cnc intraday margin mtf co bo])
      end

      it 'can be set to intraday' do
        order = build(:order, product_type: 'intraday')
        expect(order.intraday?).to be true
      end

      it 'can be set to cnc' do
        order = build(:order, product_type: 'cnc')
        expect(order.cnc?).to be true
      end
    end

    describe 'order_type' do
      it 'has correct order types' do
        expect(described_class.order_types.keys).to match_array(%w[limit market stop_loss stop_loss_market])
      end

      it 'can be set to market' do
        order = build(:order, order_type: 'market')
        expect(order.order_type_market?).to be true
      end

      it 'can be set to limit' do
        order = build(:order, order_type: 'limit')
        expect(order.order_type_limit?).to be true
      end

      it 'can be set to stop_loss' do
        order = build(:order, order_type: 'stop_loss')
        expect(order.order_type_stop_loss?).to be true
      end
    end

    describe 'validity' do
      it 'has correct validity types' do
        expect(described_class.validities.keys).to match_array(%w[day ioc])
      end

      it 'can be set to day' do
        order = build(:order, validity: 'day')
        expect(order.day?).to be true
      end

      it 'can be set to ioc' do
        order = build(:order, validity: 'ioc')
        expect(order.ioc?).to be true
      end
    end

    describe 'order_status' do
      it 'has correct order statuses' do
        expect(described_class.order_statuses.keys).to match_array(%w[transit pending rejected cancelled traded expired])
      end

      it 'can be set to pending' do
        order = build(:order, order_status: 'pending')
        expect(order.pending?).to be true
      end

      it 'can be set to traded' do
        order = build(:order, order_status: 'traded')
        expect(order.traded?).to be true
      end

      it 'can be set to rejected' do
        order = build(:order, order_status: 'rejected')
        expect(order.rejected?).to be true
      end
    end
  end

  describe 'scopes and queries' do
    let!(:pending_order) { create(:order, order_status: 'pending', security_id: '11536') }
    let!(:traded_order) { create(:order, order_status: 'traded', security_id: '408065') }
    let!(:rejected_order) { create(:order, order_status: 'rejected', security_id: '1333') }

    it 'can find pending orders' do
      expect(described_class.pending).to include(pending_order)
      expect(described_class.pending).not_to include(traded_order, rejected_order)
    end

    it 'can find traded orders' do
      expect(described_class.traded).to include(traded_order)
      expect(described_class.traded).not_to include(pending_order, rejected_order)
    end

    it 'can find rejected orders' do
      expect(described_class.rejected).to include(rejected_order)
      expect(described_class.rejected).not_to include(pending_order, traded_order)
    end
  end

  describe 'factory' do
    it 'creates a valid order' do
      order = build(:order)
      expect(order).to be_valid
    end

    it 'creates an order with required dhan_order_id' do
      order = create(:order)
      expect(order.dhan_order_id).to be_present
    end
  end
end
