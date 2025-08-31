# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PriceMath do
  describe '.round_tick' do
    it 'rounds prices to nearest tick' do
      expect(PriceMath.round_tick(100.12)).to eq(100.10)
      expect(PriceMath.round_tick(100.13)).to eq(100.15)
      expect(PriceMath.round_tick(100.17)).to eq(100.15)
      expect(PriceMath.round_tick(100.18)).to eq(100.20)
    end

    it 'handles nil values' do
      expect(PriceMath.round_tick(nil)).to be_nil
    end

    it 'handles zero values' do
      expect(PriceMath.round_tick(0)).to eq(0.0)
    end

    it 'handles negative values' do
      expect(PriceMath.round_tick(-100.12)).to eq(-100.10)
      expect(PriceMath.round_tick(-100.13)).to eq(-100.15)
    end
  end

  describe '.floor_tick' do
    it 'floors prices to nearest tick below' do
      expect(PriceMath.floor_tick(100.12)).to eq(100.10)
      expect(PriceMath.floor_tick(100.13)).to eq(100.10)
      expect(PriceMath.floor_tick(100.17)).to eq(100.15)
      expect(PriceMath.floor_tick(100.18)).to eq(100.15)
    end
  end

  describe '.ceil_tick' do
    it 'ceils prices to nearest tick above' do
      expect(PriceMath.ceil_tick(100.12)).to eq(100.15)
      expect(PriceMath.ceil_tick(100.13)).to eq(100.15)
      expect(PriceMath.ceil_tick(100.17)).to eq(100.20)
      expect(PriceMath.ceil_tick(100.18)).to eq(100.20)
    end
  end

  describe '.valid_tick?' do
    it 'validates tick-aligned prices' do
      expect(PriceMath.valid_tick?(100.10)).to be true
      expect(PriceMath.valid_tick?(100.15)).to be true
      expect(PriceMath.valid_tick?(100.20)).to be true
      expect(PriceMath.valid_tick?(100.12)).to be false
      expect(PriceMath.valid_tick?(100.13)).to be false
    end

    it 'handles nil values' do
      expect(PriceMath.valid_tick?(nil)).to be false
    end
  end

  describe '.round_legacy' do
    it 'rounds to 2 decimal places for backward compatibility' do
      expect(PriceMath.round_legacy(100.123)).to eq(100.12)
      expect(PriceMath.round_legacy(100.125)).to eq(100.13)
      expect(PriceMath.round_legacy(100.126)).to eq(100.13)
    end
  end
end
