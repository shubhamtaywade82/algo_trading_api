# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IntradayAnalysis, type: :model do # rubocop:disable RSpecRails/InferredSpecType
  describe 'validations' do
    it { is_expected.to validate_presence_of(:symbol) }
    it { is_expected.to validate_presence_of(:timeframe) }
    it { is_expected.to validate_presence_of(:atr) }
    it { is_expected.to validate_presence_of(:atr_pct) }
    it { is_expected.to validate_presence_of(:calculated_at) }
  end

  describe 'scopes' do
    let!(:most_recent_reliance_5m) do
      create(:intraday_analysis, symbol: 'RELIANCE', timeframe: '5m', calculated_at: 1.hour.ago)
    end

    before do
      create(:intraday_analysis, symbol: 'RELIANCE', timeframe: '15m', calculated_at: 2.hours.ago)
      create(:intraday_analysis, symbol: 'TCS', timeframe: '5m', calculated_at: 30.minutes.ago)
    end

    describe '.for_symbol_timeframe' do
      it 'returns a relation filtered by symbol and timeframe, ordered by calculated_at desc' do
        relation = described_class.for_symbol_timeframe('RELIANCE', '5m')
        expect(relation).to be_a(ActiveRecord::Relation)
        expect(relation.pluck(:id)).to eq([most_recent_reliance_5m.id])
      end
    end

    describe '.get_for' do
      it 'returns the most recent analysis for a symbol and timeframe' do
        result = described_class.get_for('RELIANCE', '5m')
        expect(result).to eq(most_recent_reliance_5m)
      end

      it 'defaults to 5m timeframe when not specified' do
        result = described_class.get_for('RELIANCE')
        expect(result).to eq(most_recent_reliance_5m)
      end

      it 'returns nil when no analysis found' do
        result = described_class.get_for('NONEXISTENT')
        expect(result).to be_nil
      end

      it 'is case insensitive for symbol' do
        result = described_class.get_for('reliance', '5m')
        expect(result).to eq(most_recent_reliance_5m)
      end
    end
  end
end
