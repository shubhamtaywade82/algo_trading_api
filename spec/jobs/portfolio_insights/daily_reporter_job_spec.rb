require 'rails_helper'

RSpec.describe PortfolioInsights::DailyReporterJob do
  describe '#perform' do
    let(:holdings) { [{ 'symbol' => 'RELIANCE', 'quantity' => 100, 'ltp' => 2500 }] }

    context 'unit tests (internal services stubbed)' do
      before do
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
      end

      it 'calls PortfolioInsights::Analyzer with holdings' do
        described_class.perform_now
        expect(PortfolioInsights::Analyzer).to have_received(:call).with(dhan_holdings: holdings)
      end

      it 'runs without errors' do
        expect { described_class.perform_now }.not_to raise_error
      end
    end

    context 'when API fetch fails' do
      before do
        api_module = Module.new
        holdings_class = Class.new do
          def self.fetch
            []
          end
        end
        api_module.const_set(:Holdings, holdings_class)
        stub_const('Dhanhq::API', api_module)
        allow(Dhanhq::API::Holdings).to receive(:fetch).and_raise(StandardError, 'API failed')
        allow(PortfolioInsights::Analyzer).to receive(:call)
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'API failed')
      end
    end

    context 'when analyzer fails' do
      before do
        api_module = Module.new
        holdings_class = Class.new do
          def self.fetch
            []
          end
        end
        api_module.const_set(:Holdings, holdings_class)
        stub_const('Dhanhq::API', api_module)
        allow(Dhanhq::API::Holdings).to receive(:fetch).and_return(holdings)
        allow(PortfolioInsights::Analyzer).to receive(:call).and_raise(StandardError, 'Analysis failed')
      end

      it 'raises the error' do
        expect { described_class.perform_now }.to raise_error(StandardError, 'Analysis failed')
      end
    end

    # Stub only external boundaries; real Analyzer runs.
    context 'integration: stubs only external boundaries' do
      let(:holdings_fixture) do
        [
          {
            'securityId' => '123',
            'exchangeSegment' => 'NSE_EQ',
            'tradingSymbol' => 'RELIANCE',
            'totalQty' => 100,
            'avgCostPrice' => 2400.0,
            'instrumentType' => 'EQUITY',
            'tradeType' => 'Delivery'
          }
        ]
      end

      before do
        allow(Dhanhq::API::Holdings).to receive(:fetch).and_return(holdings_fixture)
        allow(DhanHQ::Models::Funds).to receive(:fetch).and_return(double(available_balance: 100_000.0))
        allow(Dhanhq::API::MarketFeed).to receive(:ltp).and_return(
          'data' => { 'NSE_EQ' => { '123' => { 'last_price' => 2500.0 } } }
        )
        allow(Openai::ChatRouter).to receive(:ask!).and_return('AI portfolio summary — end of brief')
        allow(TelegramNotifier).to receive(:send_chat_action)
        allow(TelegramNotifier).to receive(:send_message)
        allow(PortfolioInsights::Analyzer).to receive(:call).and_call_original
      end

      it 'runs job and real Analyzer with only external APIs stubbed' do
        expect { described_class.perform_now }.not_to raise_error
        expect(Dhanhq::API::Holdings).to have_received(:fetch)
        expect(Openai::ChatRouter).to have_received(:ask!).with(
          a_string_including('CASH AVAILABLE', 'RELIANCE', '2500'),
          hash_including(system: a_string_including('Indian equity portfolio'))
        )
      end
    end
  end
end
