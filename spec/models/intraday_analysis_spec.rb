require 'rails_helper'

RSpec.describe IntradayAnalysis, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:symbol) }
    it { is_expected.to validate_presence_of(:timeframe) }
    it { is_expected.to validate_presence_of(:atr) }
    it { is_expected.to validate_presence_of(:atr_pct) }
    it { is_expected.to validate_presence_of(:calculated_at) }
  end

  describe 'scopes' do
    let!(:analysis1) { create(:intraday_analysis, symbol: 'RELIANCE', timeframe: '5m', calculated_at: 1.hour.ago) }
    let!(:analysis2) { create(:intraday_analysis, symbol: 'RELIANCE', timeframe: '15m', calculated_at: 2.hours.ago) }
    let!(:analysis3) { create(:intraday_analysis, symbol: 'TCS', timeframe: '5m', calculated_at: 30.minutes.ago) }

    describe '.get_for' do
      it 'returns the most recent analysis for a symbol and timeframe' do
        result = IntradayAnalysis.get_for('RELIANCE', '5m')
        expect(result).to eq(analysis1)
      end

      it 'defaults to 5m timeframe when not specified' do
        result = IntradayAnalysis.get_for('RELIANCE')
        expect(result).to eq(analysis1)
      end

      it 'returns nil when no analysis found' do
        result = IntradayAnalysis.get_for('NONEXISTENT')
        expect(result).to be_nil
      end

      it 'is case insensitive for symbol' do
        result = IntradayAnalysis.get_for('reliance', '5m')
        expect(result).to eq(analysis1)
      end
    end
  end
end
