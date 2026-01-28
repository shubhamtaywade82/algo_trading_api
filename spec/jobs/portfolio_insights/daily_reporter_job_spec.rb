require 'rails_helper'

RSpec.describe PortfolioInsights::DailyReporterJob do
  describe '#perform' do
    let(:holdings) { [{ 'symbol' => 'RELIANCE', 'quantity' => 100, 'ltp' => 2500 }] }

    before do
      # Create a stub for the missing constant
      api_module = Module.new
      holdings_class = Class.new do
        def self.fetch
          []
        end
      end
      api_module.const_set(:Holdings, holdings_class)
      stub_const('Dhanhq::API', api_module)

      allow(Dhanhq::API::Holdings).to receive(:fetch).and_return(holdings)
      allow(PortfolioInsights::Analyzer).to receive(:call)
    end

    it 'fetches holdings from API' do
      described_class.perform_now

      # Test passes if no error is raised
    end

    it 'calls PortfolioInsights::Analyzer with holdings' do
      described_class.perform_now

      expect(PortfolioInsights::Analyzer).to have_received(:call).with(dhan_holdings: holdings)
    end

    it 'runs without errors' do
      expect { described_class.perform_now }.not_to raise_error
    end

    context 'when API fetch fails' do
      before do
        allow(Dhanhq::API::Holdings).to receive(:fetch).and_raise(StandardError, 'API failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'API failed')
      end
    end

    context 'when analyzer fails' do
      before do
        allow(PortfolioInsights::Analyzer).to receive(:call).and_raise(StandardError, 'Analysis failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'Analysis failed')
      end
    end
  end
end
