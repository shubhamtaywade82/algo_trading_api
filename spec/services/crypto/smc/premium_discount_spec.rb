# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Crypto::Smc::PremiumDiscount do
  subject(:pd) { described_class.new(high: 200.0, low: 100.0) }

  it 'puts equilibrium at the midpoint' do
    expect(pd.equilibrium).to eq(150.0)
  end

  describe '#zone' do
    it 'calls the lower half discount and the upper half premium' do
      expect(pd.zone(120.0)).to eq(:discount)
      expect(pd.zone(180.0)).to eq(:premium)
    end

    it 'treats a band around the midpoint as equilibrium rather than flipping on a tick' do
      expect(pd.zone(150.0)).to eq(:equilibrium)
      expect(pd.zone(152.0)).to eq(:equilibrium)
    end
  end

  describe '#favourable?' do
    it 'wants longs in discount and shorts in premium' do
      expect(pd.favourable?(120.0, :bullish)).to be(true)
      expect(pd.favourable?(180.0, :bullish)).to be(false)
      expect(pd.favourable?(180.0, :bearish)).to be(true)
      expect(pd.favourable?(120.0, :bearish)).to be(false)
    end

    it 'allows equilibrium either way' do
      expect(pd.favourable?(150.0, :bullish)).to be(true)
      expect(pd.favourable?(150.0, :bearish)).to be(true)
    end
  end

  describe '#ote' do
    it 'sits in the lower half of the range for a long' do
      band = pd.ote(:bullish)

      expect(band[:bottom]).to be_within(0.01).of(121.0) # 200 - 79
      expect(band[:top]).to be_within(0.01).of(138.2)    # 200 - 61.8
      expect(pd.in_ote?(130.0, :bullish)).to be(true)
      expect(pd.in_ote?(190.0, :bullish)).to be(false)
    end

    it 'mirrors into the upper half for a short' do
      band = pd.ote(:bearish)

      expect(band[:bottom]).to be_within(0.01).of(161.8)
      expect(band[:top]).to be_within(0.01).of(179.0)
    end
  end

  context 'without a usable range' do
    it 'answers nil rather than dividing by zero' do
      empty = described_class.new(nil)

      expect(empty).not_to be_valid
      expect(empty.zone(100.0)).to be_nil
      expect(empty.favourable?(100.0, :bullish)).to be(false)
      expect(empty.ote(:bullish)).to be_nil
    end
  end
end
